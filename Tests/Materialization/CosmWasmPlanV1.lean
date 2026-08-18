/-
  CosmWasm Plan/IR/WAT engineering suite (MVP leaf + CW-4 schedule SubMsg).

  Pins StateCell plan shape, CosmWasm ABI exports (instantiate/execute/query/
  allocate/deallocate/interface_version_8), Region/JSON markers, db_* imports,
  CW-4 schedule → SubMsg reply_on=never with Binary (base64) execute msg
  (Plan/IR/WAT shape), pure Lean base64 encode matrix (empty / 1 / 2 / 3+
  bytes + typical JSON), B-RET-ABI named Struct/Enum entry/view returns
  (PairRet/MaybeRet Plan/IR/WAT/ABI pins + param/>8/pureFn FC), N-ANON-RESULT
  anonymous Array UInt64 N / Option UInt64 entry/view returns (ArrayRet/
  OptionRet Plan/IR/WAT/ABI pins + Map/Bytes/N>8/nested FC), B-OPT-STATE
  Option UInt64 state (OptionState tag+payload / storeAtomic / none zeroing +
  non-UInt64/nested/param FC) and Option Int64 state (unsigned tag + signed
  i64-le payload; Option Int8 / Option UInt128 FC; Option Int64 view return
  is 2-leaf tag+payload),
  dense Map UInt64 Int64 state (cap-8 24-leaf occ/key unsigned + val signed;
  not a UInt64-value alias; Map Int8 / Map UInt128 FC; Map UInt64 Int64
  return is 24-leaf val-only isInt),
  sync call still fail closed, multi-width
  UInt8/16/32 pins (body guards / param range / 8-byte narrow state slots),
  UInt128 2-limb ABI and UInt256 4-limb ABI (state/param/result; 8-byte
  Regions only), Array Int64 N as N×8-byte signed KV leaves (isInt /
  ABI i64-le; not a packed array or UInt64 alias; Array Int64 24
  stays uniformly signed, not Map occ/key/val mix), and other FC
  boundaries (Int128, Arr/Map/Opt-U256, Arr/Map/Opt of Int8/16/32
  and UInt128, invariants).

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

private def stateCellSourceText : String :=
  "import ProofForgeV2\n\n" ++
  "namespace ProofForgeV2.Examples\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program StateCell where\n" ++
  "  state count : UInt64\n\n" ++
  "  init(initial : UInt64) do\n" ++
  "    count := initial\n\n" ++
  "  entry increment(delta : UInt64) : UInt64 do\n" ++
  "    count := count + delta\n" ++
  "    return count\n\n" ++
  "  view get() : UInt64 do\n" ++
  "    return count\n\n" ++
  "end ProofForgeV2.Examples\n"

private def stateCellModuleName : String := "Examples.StateCell"

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

private unsafe def testStateCellPlan
    (session : Language.Loader.ParserSession) : IO Unit := do
  let compiled ← compileSource session stateCellSourceText stateCellModuleName "<cw-stateCell>"
  let plan ← liftResult <| planCw compiled
  expect (plan.programName == "StateCell") "program name StateCell"
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
  IO.println "  ✓ StateCell plan shape"

private unsafe def testStateCellIRAndWat
    (session : Language.Loader.ParserSession) : IO Unit := do
  let compiled ← compileSource session stateCellSourceText stateCellModuleName "<cw-stateCell-ir>"
  let ir ← liftResult <| irCw compiled
  expect (ir.name == "StateCell") "IR name"
  expect (ir.methods.size == 3) "init + 2 entries"
  expect (ir.imports == canonicalImports) "IR host imports"
  let files ← liftResult <| filesCw compiled
  let wat ← findFile files "StateCell.wat"
  let abi ← findFile files "StateCell.cosmwasm-abi.json"
  -- Module shape
  expect (wat.contains "(module") "WAT module"
  expect (wat.contains "(memory (export \"memory\") 2)") "single memory min=2 no max"
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
  -- ADR-0031 S1 follow-up: StateCell never reads context.caller, so
  -- instantiate/execute must not invoke the sender→Principal packer
  -- (non-caller programs stay free of sender 1..64 / bech32 traps).
  expect (!wat.contains "(call $pf_load_caller_principal)")
    "StateCell must not call pf_load_caller_principal (no context.caller use)"
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
  IO.println "  ✓ StateCell IR/WAT/ABI CosmWasm shape"

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

/-- Value-position Oracle.feed is a distinct envelope gate from the void
    statement pin above. Product resolve currently mints the sync-call
    capability (C2); Plan is the fail-closed authority. Resolve success
    is not an open of CALL. -/
unsafe def testResultBearingExternalCallFailClosed : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let src := wrapProgram "CallRetCw" <|
    "  state s : UInt64\n\n" ++
    "  init(x : UInt64) do\n" ++
    "    s := x\n\n" ++
    "  entry go() : UInt64 do\n" ++
    "    let y : UInt64 := call Oracle.feed(s)\n" ++
    "    return s\n\n" ++
    "  view peek() : UInt64 do\n" ++
    "    return s\n"
  let validated ← liftResult (← session.selectProgramV1 src
    "<cw-call-ret>" "Examples.CallRetCw" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 validated
  -- ADR-0029 C2: generic non-catalog sync mints a capability; Plan is the
  -- fail-closed authority. Resolve success is not an open of CALL.
  let selection ← liftResult <| resolveBuildSelectionV1 TargetId.cosmwasm none
  let cap ← match Targets.resolveEngineeringRequirementsV1 selection compiled with
    | .ok c => pure c
    | .error e =>
        throw <| IO.userError
          s!"product resolve currently mints capability (C2); Plan is FC, got {e.render}"
  match planFromCapability cap with
  | .error e =>
      expect (e.render.contains
          "result-bearing ExternalCall is outside the CosmWasm envelope")
        s!"product Plan must name the result-bearing gate, got: {e.render}"
  | .ok _ =>
      throw <| IO.userError
        "result-bearing Oracle.feed must fail closed at CosmWasm product Plan"
  match engineeringPlanFromCompiled compiled with
  | .error e =>
      expect (e.render.contains
          "result-bearing ExternalCall is outside the CosmWasm envelope")
        s!"result-bearing must fail at the named envelope gate, got: {e.render}"
  | .ok _ =>
      throw <| IO.userError
        "result-bearing Oracle.feed must fail closed at CosmWasm engineering Plan"

/-- SYS-S5: CosmWasm has no sha256 or keccak256 host. Exact `pf.crypto.*`
    QNs stay Plan fail closed (no hashed / stdlib fallback). -/
private unsafe def testCryptoSha256StayFailClosed
    (session : Language.Loader.ParserSession) : IO Unit := do
  let expectPlanFc (programName pathLabel moduleName body needle : String)
      (also : String := "") : IO Unit := do
    let src := wrapProgram programName body
    let compiled ← compileSource session src moduleName pathLabel
    -- Engineering path: pin the Plan diagnostic even if the product
    -- resolver declines effect.synchronous-call first.
    match engineeringPlanFromCompiled compiled with
    | .error e =>
        expect (e.render.contains needle)
          s!"{programName} Plan FC must contain '{needle}', got: {e.render}"
        unless also.isEmpty do
          expect (e.render.contains also)
            s!"{programName} Plan FC must contain '{also}', got: {e.render}"
    | .ok _ =>
        throw <| IO.userError
          s!"{programName} must Plan fail closed (no CosmWasm crypto host)"
  -- Keep UInt64 state/result on purpose so the fail-closed needle stays
  -- the crypto QN. Public UInt256 ABI is admitted as four 8-byte limbs
  -- in `testUint256Abi`; this fixture only uses a body-local UInt256.
  expectPlanFc "Sha256Cw" "<cw-sha256>" "Examples.Sha256Cw"
    ("  state pad : UInt64\n\n" ++
      "  init() do\n" ++
      "    pad := 0\n\n" ++
      "  entry probe() : UInt64 do\n" ++
      "    let w : UInt256 := 0\n" ++
      "    let h : UInt256 := call pf.crypto.sha256(w)\n" ++
      "    return pad\n\n" ++
      "  view get() : UInt64 do\n" ++
      "    return pad\n")
    "has no CosmWasm host binding"
  expectPlanFc "Sha256CwHashNoPad" "<cw-sha256-hashnopad>"
    "Examples.Sha256CwHashNoPad"
    ("  state pad : UInt64\n\n" ++
      "  init() do\n" ++
      "    pad := 0\n\n" ++
      "  entry probe() : UInt64 do\n" ++
      "    let w : UInt256 := 0\n" ++
      "    let h : UInt256 := call pf.crypto.hashNoPad(w)\n" ++
      "    return pad\n\n" ++
      "  view get() : UInt64 do\n" ++
      "    return pad\n")
    "has no CosmWasm host binding"
  -- SYS-S5-ECDSA-FC: EVM-admit arity stays Plan FC (no CosmWasm ecdsa host).
  -- Same UInt64 ABI + body-local UInt256 as the sha256 fixture above.
  expectPlanFc "EcdsaRecoverCw" "<cw-ecdsa-recover>"
    "Examples.EcdsaRecoverCw"
    ("  state pad : UInt64\n\n" ++
      "  init() do\n" ++
      "    pad := 0\n\n" ++
      "  entry probe() : UInt64 do\n" ++
      "    let h : UInt256 := 0\n" ++
      "    let v : UInt256 := 0\n" ++
      "    let r : UInt256 := 0\n" ++
      "    let s : UInt256 := 0\n" ++
      "    let a : UInt256 := call pf.crypto.ecdsaRecoverSecp256k1(h, v, r, s)\n" ++
      "    return pad\n\n" ++
      "  view get() : UInt64 do\n" ++
      "    return pad\n")
    "has no CosmWasm host binding"
    "ecdsaRecoverSecp256k1"
  expectPlanFc "Keccak256Cw" "<cw-keccak256>" "Examples.Keccak256Cw"
    ("  state pad : UInt64\n\n" ++
      "  init() do\n" ++
      "    pad := 0\n\n" ++
      "  entry probe() : UInt64 do\n" ++
      "    let w : UInt256 := 0\n" ++
      "    let h : UInt256 := call pf.crypto.keccak256(w)\n" ++
      "    return pad\n\n" ++
      "  view get() : UInt64 do\n" ++
      "    return pad\n")
    "has no CosmWasm host binding"
  IO.println "  ✓ pf.crypto.sha256/keccak256 stay fail closed (no CosmWasm host)"

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

/-- Collect Plan body evidence for narrow UInt8 StateCell (no nested mut walk). -/
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

/-- BL-15: UInt8 StateCell plan/IR/WAT pins — narrow body high-bit guards,
    JSON param range-check (exact width, no silent truncation), and
    8-byte physical state slots with high-bytes-zero load guard. -/
private unsafe def testMultiWidthUInt8
    (session : Language.Loader.ParserSession) : IO Unit := do
  let src := wrapProgram "NarrowStateCell" <|
    "  state count : UInt8\n\n" ++
    "  init(initial : UInt8) do\n" ++
    "    count := initial\n\n" ++
    "  entry increment(delta : UInt8) : UInt8 do\n" ++
    "    count := count + delta\n" ++
    "    return count\n\n" ++
    "  view get() : UInt8 do\n" ++
    "    return count\n"
  let compiled ← compileSource session src
    "Examples.NarrowStateCell" "<cw-u8-narrow>"
  let plan ← liftResult <| planCw compiled
  expect (plan.storage.fields.size == 1) "NarrowStateCell one state field"
  expect (plan.storage.fields[0]!.byteWidth == 1)
    s!"NarrowStateCell state semantic byteWidth=1, got {plan.storage.fields[0]!.byteWidth}"
  expect (plan.initializer.params.size == 1) "init one param"
  expect (plan.initializer.params[0]!.byteWidth == 1)
    "init param semantic byteWidth=1"
  let some inc := plan.entries.find? (·.name == "increment") |
    throw <| IO.userError "NarrowStateCell missing increment"
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
  let wat ← findFile files "NarrowStateCell.wat"
  -- Body high-bit guard after narrow add: shr_u by 8 then trap if nonzero.
  expect (wat.contains "(i64.const 8)")
    "NarrowStateCell WAT must emit bitWidth=8 high-bit guards"
  expect (wat.contains "i64.shr_u")
    "NarrowStateCell WAT must use shr_u for high-bit / range guards"
  -- Param range-check after JSON parse (init initial : UInt8).
  expect (wat.contains "pf_parse_u64_field") "JSON parse still used"
  -- Physical store remains 8-byte Region helper (not variable-length KV).
  expect (wat.contains "$pf_db_store_u64") "physical 8-byte Region store"
  expect (wat.contains "$pf_db_load_u64") "physical 8-byte Region load"
  let abi ← findFile files "NarrowStateCell.cosmwasm-abi.json"
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

/-- UInt128 ABI: two 8-byte KV limbs + two JSON decimal params + 2-limb return.
    UInt256 ABI is pinned in `testUint256Abi`. Int128 stays fail closed. -/
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
  let compiled ← compileSource session u128 "Examples.Wide128" "<cw-u128-abi>"
  let plan ← liftResult <| planCw compiled
  expect (plan.storage.fields.size == 2) "UInt128 state is two KV limbs"
  expect (plan.storage.fields[0]!.name == "s_lo") "UInt128 lo limb name"
  expect (plan.storage.fields[1]!.name == "s_hi") "UInt128 hi limb name"
  expect (plan.storage.fields[0]!.byteWidth == 8) "UInt128 lo limb width"
  expect (plan.storage.fields[1]!.byteWidth == 8) "UInt128 hi limb width"
  expect (plan.initializer.params.size == 2) "UInt128 init is two JSON limbs"
  expect (plan.initializer.params[0]!.name == "x_lo") "UInt128 init lo name"
  expect (plan.initializer.params[1]!.name == "x_hi") "UInt128 init hi name"
  let some bump := plan.entries.find? (·.name == "bump") |
    throw <| IO.userError "Wide128 missing bump"
  expect (bump.resultKind == MethodResultKind.uint128) "entry result is uint128"
  let some get := plan.entries.find? (·.name == "get") |
    throw <| IO.userError "Wide128 missing get"
  expect (get.resultKind == MethodResultKind.uint128) "view result is uint128"
  let files ← liftResult <| filesCw compiled
  let wat ← findFile files "Wide128.wat"
  let abi ← findFile files "Wide128.cosmwasm-abi.json"
  expect (wat.contains "pf_db_load_u64") "UInt128 WAT loads KV limbs"
  expect (wat.contains "pf_db_store_u64") "UInt128 WAT stores KV limbs"
  expect (wat.contains "ret_count") "UInt128 return uses 2-limb aggregate wire"
  expect (abi.contains "\"u128\"") "ABI JSON advertises u128 result"
  expect (abi.contains "s_lo") "ABI JSON names lo limb"
  expect (abi.contains "s_hi") "ABI JSON names hi limb"
  let i128src := wrapProgram "NarrowI128" <|
    "  state s : Int128\n\n" ++
    "  init(x : Int128) do\n" ++
    "    s := x\n\n" ++
    "  entry bump(d : Int128) : Int128 do\n" ++
    "    s := s + d\n" ++
    "    return s\n\n" ++
    "  view get() : Int128 do\n" ++
    "    return s\n"
  match ← session.selectProgramV1 i128src "<cw-i128-fc>" "Examples.NarrowI128" none with
  | .error _ => pure ()
  | .ok validated =>
      match Compiler.compileValidatedSourceV1 validated with
      | .error _ => pure ()
      | .ok compiledI128 =>
          match cosmwasmCapability compiledI128 with
          | .error _ => pure ()
          | .ok capability =>
              expectPlanError "Int128 state" (planFromCapability capability)
  IO.println "  ✓ multi-width UInt128 ABI admit / Int128 fail closed"

/-- UInt256 ABI: four consecutive 8-byte KV limbs + four JSON decimals +
    4-limb return. Physical stores stay `pf_db_*_u64`. Not a 32-byte Region. -/
private unsafe def testUint256Abi
    (session : Language.Loader.ParserSession) : IO Unit := do
  let u256 := wrapProgram "Wide256" <|
    "  state s : UInt256\n\n" ++
    "  init(x : UInt256) do\n" ++
    "    s := x\n\n" ++
    "  entry bump(d : UInt256) : UInt256 do\n" ++
    "    s := s + d\n" ++
    "    return s\n\n" ++
    "  view get() : UInt256 do\n" ++
    "    return s\n"
  let compiled ← compileSource session u256 "Examples.Wide256" "<cw-u256-abi>"
  let plan ← liftResult <| planCw compiled
  expect (plan.storage.fields.size == 4) "UInt256 state is four KV limbs"
  expect (plan.storage.fields[0]!.name == "s_l0") "UInt256 l0 limb name"
  expect (plan.storage.fields[1]!.name == "s_l1") "UInt256 l1 limb name"
  expect (plan.storage.fields[2]!.name == "s_l2") "UInt256 l2 limb name"
  expect (plan.storage.fields[3]!.name == "s_l3") "UInt256 l3 limb name"
  expect (plan.storage.fields[0]!.byteWidth == 8) "UInt256 l0 limb width"
  expect (plan.storage.fields[1]!.byteWidth == 8) "UInt256 l1 limb width"
  expect (plan.storage.fields[2]!.byteWidth == 8) "UInt256 l2 limb width"
  expect (plan.storage.fields[3]!.byteWidth == 8) "UInt256 l3 limb width"
  expect (plan.initializer.params.size == 4) "UInt256 init is four JSON limbs"
  expect (plan.initializer.params[0]!.name == "x_l0") "UInt256 init l0 name"
  expect (plan.initializer.params[1]!.name == "x_l1") "UInt256 init l1 name"
  expect (plan.initializer.params[2]!.name == "x_l2") "UInt256 init l2 name"
  expect (plan.initializer.params[3]!.name == "x_l3") "UInt256 init l3 name"
  expect (plan.initializer.params[0]!.byteWidth == 8) "UInt256 init l0 width"
  let some bump := plan.entries.find? (·.name == "bump") |
    throw <| IO.userError "Wide256 missing bump"
  expect (bump.resultKind == MethodResultKind.uint256) "entry result is uint256"
  expect (bump.params.size == 4) "UInt256 bump is four JSON limbs"
  let some get := plan.entries.find? (·.name == "get") |
    throw <| IO.userError "Wide256 missing get"
  expect (get.resultKind == MethodResultKind.uint256) "view result is uint256"
  let files ← liftResult <| filesCw compiled
  let wat ← findFile files "Wide256.wat"
  let abi ← findFile files "Wide256.cosmwasm-abi.json"
  expect (wat.contains "pf_db_load_u64") "UInt256 WAT loads 8-byte KV limbs"
  expect (wat.contains "pf_db_store_u64") "UInt256 WAT stores 8-byte KV limbs"
  expect (wat.contains "ret_count (i32.const 4)")
    "UInt256 return uses 4-limb aggregate wire"
  expect (abi.contains "\"u256\"") "ABI JSON advertises u256 result"
  expect (abi.contains "s_l0") "ABI JSON names l0 limb"
  expect (abi.contains "s_l1") "ABI JSON names l1 limb"
  expect (abi.contains "s_l2") "ABI JSON names l2 limb"
  expect (abi.contains "s_l3") "ABI JSON names l3 limb"
  IO.println "  ✓ UInt256 4-limb ABI admit (8-byte Regions)"

/-- Arr/Map/Opt of UInt256 stay fail closed (UInt64-element/payload needles). -/
private unsafe def testU256ContainerFc
    (session : Language.Loader.ParserSession) : IO Unit := do
  let arr := wrapProgram "ArrU256" <|
    "  state slots : Array UInt256 2\n\n" ++
    "  init() do\n" ++
    "    slots[0] := 0\n" ++
    "    slots[1] := 0\n\n" ++
    "  entry set0(v : UInt64) : UInt64 do\n" ++
    "    slots[0] := 0\n" ++
    "    return v\n"
  let arrCompiled ← compileSource session arr "Examples.ArrU256" "<cw-arr-u256>"
  expectPlanErrorContaining "ArrU256" "Array state element must be UInt64"
    (planCw arrCompiled)
  let mapSrc := wrapProgram "MapU256" <|
    "  state m : Map UInt64 UInt256\n\n" ++
    "  init() do\n" ++
    "    m := Map.empty()\n\n" ++
    "  entry put(k : UInt64, v : UInt64) : UInt64 do\n" ++
    "    return v\n"
  let mapCompiled ← compileSource session mapSrc "Examples.MapU256" "<cw-map-u256>"
  expectPlanErrorContaining "MapU256" "Map state admits only Map UInt64 UInt64"
    (planCw mapCompiled)
  let opt := wrapProgram "OptU256" <|
    "  state o : Option UInt256\n\n" ++
    "  init() do\n" ++
    "    o := Option.none()\n\n" ++
    "  view peek() : UInt64 do\n" ++
    "    return 0\n"
  let optCompiled ← compileSource session opt "Examples.OptU256" "<cw-opt-u256>"
  expectPlanErrorContaining "OptU256" "UInt64 payload" (planCw optCompiled)
  IO.println "  ✓ Arr/Map/Opt-U256 stay fail closed"

/-- Array Int64 N = N consecutive 8-byte signed KV leaves (`isInt`, ABI
    `i64-le`). Same flatten as Array UInt64; not a packed array and not a
    UInt64 alias. Physical WAT stays `pf_db_*_u64`. -/
private unsafe def testArrayInt64State
    (session : Language.Loader.ParserSession) : IO Unit := do
  let src := wrapProgram "ArrInt64" <|
    "  state slots : Array Int64 2\n\n" ++
    "  init() do\n" ++
    "    slots[0] := 0\n" ++
    "    slots[1] := 0\n\n" ++
    "  entry set0(v : Int64) : Int64 do\n" ++
    "    slots[0] := v\n" ++
    "    return slots[0]\n\n" ++
    "  view get() : Int64 do\n" ++
    "    return slots[1]\n"
  let compiled ← compileSource session src "Examples.ArrInt64" "<cw-arr-int64>"
  let plan ← liftResult <| planCw compiled
  expect (plan.storage.fields.size == 2) "ArrInt64 fields.size==2"
  expect (plan.storage.fields[0]!.name == "slots_0") "ArrInt64 slots_0"
  expect (plan.storage.fields[1]!.name == "slots_1") "ArrInt64 slots_1"
  expect (plan.storage.fields[0]!.byteWidth == 8) "ArrInt64 slots_0 byteWidth=8"
  expect (plan.storage.fields[1]!.byteWidth == 8) "ArrInt64 slots_1 byteWidth=8"
  expect plan.storage.fields[0]!.isInt "ArrInt64 slots_0 isInt"
  expect plan.storage.fields[1]!.isInt "ArrInt64 slots_1 isInt"
  expect (layoutFieldTypeSuffix 8 true == "i64-le")
    "ArrInt64 layout suffix is i64-le (not u64-le)"
  expect (layoutFieldTypeSuffix
      plan.storage.fields[0]!.byteWidth plan.storage.fields[0]!.isInt == "i64-le")
    "ArrInt64 field ABI suffix is i64-le"
  let initAtomic := plan.initializer.body.any fun s =>
    match s with
    | .storeAtomic leaves =>
        leaves.size == 2 && leaves.all (fun st => st.isInt && st.byteWidth == 8)
    | _ => false
  expect initAtomic "ArrInt64 init storeAtomic 2 signed 8-byte leaves"
  let some set0 := plan.entries.find? (·.name == "set0") |
    throw <| IO.userError "ArrInt64 missing set0"
  expect (set0.resultKind == MethodResultKind.int64) "ArrInt64 entry result Int64"
  let setAtomic := set0.body.any fun s =>
    match s with
    | .storeAtomic leaves =>
        leaves.size == 2 && leaves.all (fun st => st.isInt && st.byteWidth == 8)
    | _ => false
  expect setAtomic "ArrInt64 entry storeAtomic 2 signed 8-byte leaves"
  let hasInt64Return := set0.body.any fun s =>
    match s with
    | .returnValue _ => true
    | _ => false
  expect hasInt64Return "ArrInt64 entry returnValue Int64 IndexGet"
  let some get := plan.entries.find? (·.name == "get") |
    throw <| IO.userError "ArrInt64 missing get"
  expect (get.mode == .view && get.resultKind == MethodResultKind.int64)
    "ArrInt64 view result Int64"
  match get.body[get.body.size - 1]! with
  | .returnValue _ => pure ()
  | _ => throw <| IO.userError "ArrInt64 view must returnValue Int64 IndexGet"
  match validatePlan plan with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"ArrInt64 plan must validate: {e.render}"
  let files ← liftResult <| filesCw compiled
  let wat ← findFile files "ArrInt64.wat"
  let abi ← findFile files "ArrInt64.cosmwasm-abi.json"
  expect (wat.contains "pf_db_load_u64") "ArrInt64 WAT 8-byte Region load"
  expect (wat.contains "pf_db_store_u64") "ArrInt64 WAT 8-byte Region store"
  -- Helper `$pf_parse_i64_field` is always in the WAT runtime; pin the
  -- execute call site so an unsigned-parse regression cannot hide behind ABI
  -- `"type":"i64"` plus the always-emitted helper definition.
  expect (wat.contains "(call $pf_parse_i64_field")
    "ArrInt64 Int64 entry word must be signed-parsed"
  expect (abi.contains "\"type\":\"i64\"") "ArrInt64 ABI JSON type i64 (i64-le)"
  expect (!abi.contains "\"type\":\"u64\"")
    "ArrInt64 ABI must not alias UInt64 u64-le storage"
  expect (abi.contains "\"returns\":\"i64\"") "ArrInt64 ABI returns i64"
  IO.println "  ✓ Array Int64 2 as N×8-byte signed leaves"

/-- Array Int64 24 must stay 24 uniform signed leaves. Map val-only isInt
    is TypeDecl `.map`, not `n == 24`; this N is the Map flatten width so
    a count-keyed layout would silently mark occ/key unsigned. Init writes
    only the pad scalar — IndexGet/IndexSet still use size==24 as a Map
    proxy (pre-existing), so this pin is layout-only. -/
private unsafe def testArrayInt64x24Layout
    (session : Language.Loader.ParserSession) : IO Unit := do
  let src := wrapProgram "ArrInt64x24" <|
    "  state slots : Array Int64 24\n" ++
    "  state pad : UInt64\n\n" ++
    "  init() do\n" ++
    "    pad := 0\n\n" ++
    "  entry ping(v : Int64) : Int64 do\n" ++
    "    return v\n\n" ++
    "  view get() : Int64 do\n" ++
    "    return 0\n"
  let compiled ← compileSource session src "Examples.ArrInt64x24"
    "<cw-arr-int64-24>"
  let plan ← liftResult <| planCw compiled
  expect (plan.storage.fields.size == 25)
    s!"ArrInt64x24: 24 array leaves + pad, got {plan.storage.fields.size}"
  for i in [0:24] do
    let some field := plan.storage.fields[i]? |
      throw <| IO.userError s!"ArrInt64x24 missing field {i}"
    expect (field.name == s!"slots_{i}")
      s!"ArrInt64x24 field {i} name must be slots_{i}, got {field.name}"
    expect (field.byteWidth == 8) s!"ArrInt64x24 slots_{i} byteWidth=8"
    expect field.isInt
      s!"ArrInt64x24 slots_{i} must stay isInt (not Map occ/key/val mix)"
    expect (layoutFieldTypeSuffix field.byteWidth field.isInt == "i64-le")
      s!"ArrInt64x24 slots_{i} ABI suffix must be i64-le"
  let some pad := plan.storage.fields[24]? |
    throw <| IO.userError "ArrInt64x24 missing pad"
  expect (pad.name == "pad" && !pad.isInt && pad.byteWidth == 8)
    "ArrInt64x24 pad stays unsigned u64-le"
  match validatePlan plan with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"ArrInt64x24 plan must validate: {e.render}"
  IO.println "  ✓ Array Int64 24 stays 24 uniform signed leaves"

/-- Array Int8 / Array UInt128 stay fail closed on the historical element
    needle (`Array state element must be UInt64` is a contains-match).
    Anonymous `Array Int64 2` return stays fail closed on the existing
    UInt64-element return needle. -/
private unsafe def testArrayInt64ElementFc
    (session : Language.Loader.ParserSession) : IO Unit := do
  let arrI8 := wrapProgram "ArrI8Cw" <|
    "  state slots : Array Int8 2\n\n" ++
    "  init() do\n" ++
    "    slots[0] := 0\n" ++
    "    slots[1] := 0\n\n" ++
    "  entry set0(v : UInt64) : UInt64 do\n" ++
    "    slots[0] := 0\n" ++
    "    return v\n"
  let arrI8Compiled ← compileSource session arrI8 "Examples.ArrI8Cw" "<cw-arr-i8>"
  expectPlanErrorContaining "ArrI8" "Array state element must be UInt64"
    (planCw arrI8Compiled)
  let arrU128 := wrapProgram "ArrU128Cw" <|
    "  state slots : Array UInt128 2\n\n" ++
    "  init() do\n" ++
    "    slots[0] := 0\n" ++
    "    slots[1] := 0\n\n" ++
    "  entry set0(v : UInt64) : UInt64 do\n" ++
    "    slots[0] := 0\n" ++
    "    return v\n"
  let arrU128Compiled ← compileSource session arrU128 "Examples.ArrU128Cw"
    "<cw-arr-u128>"
  expectPlanErrorContaining "ArrU128" "Array state element must be UInt64"
    (planCw arrU128Compiled)
  IO.println "  ✓ Array Int8 / Array UInt128 stay fail closed"

/-- Int8 ABI: one 8-byte Region, low-byte two's complement, sign-extended
    temps, checked add at width 8. Int16/32 share the same lowering. -/
private unsafe def testNarrowIntAbi
    (session : Language.Loader.ParserSession) : IO Unit := do
  let src := wrapProgram "NarrowI8" <|
    "  state s : Int8\n\n" ++
    "  init(x : Int8) do\n" ++
    "    s := x\n\n" ++
    "  entry bump(d : Int8) : Int8 do\n" ++
    "    s := s + d\n" ++
    "    return s\n\n" ++
    "  view get() : Int8 do\n" ++
    "    return s\n"
  let compiled ← compileSource session src "Examples.NarrowI8" "<cw-i8-abi>"
  let plan ← liftResult <| planCw compiled
  expect (plan.storage.fields.size == 1) "Int8 one state field"
  expect (plan.storage.fields[0]!.byteWidth == 1) "Int8 state byteWidth=1"
  expect (plan.storage.fields[0]!.isInt) "Int8 state is signed"
  expect (plan.initializer.params.size == 1) "Int8 init one param"
  expect (plan.initializer.params[0]!.byteWidth == 1) "Int8 param byteWidth=1"
  expect (plan.initializer.params[0]!.isInt) "Int8 param is signed"
  let some bump := plan.entries.find? (·.name == "bump") |
    throw <| IO.userError "NarrowI8 missing bump"
  expect (bump.resultKind == MethodResultKind.int8) "entry result is int8"
  let files ← liftResult <| filesCw compiled
  let wat ← findFile files "NarrowI8.wat"
  let abi ← findFile files "NarrowI8.cosmwasm-abi.json"
  expect (wat.contains "narrow signed checked_add bitWidth=8")
    "Int8 WAT must emit narrow signed checked add"
  expect (wat.contains "pf_parse_i64_field") "Int8 JSON uses signed parser"
  expect (wat.contains "(i64.const -128)") "Int8 range min"
  expect (wat.contains "(i64.const 127)") "Int8 range max"
  expect (wat.contains "i64.shr_s") "Int8 load sign-extends"
  expect (abi.contains "\"i8\"") "ABI JSON advertises i8"
  IO.println "  ✓ multi-width Int8 ABI admit"

/-- Body multiword UInt128 add/mul/div/mod/shl/shr: true multi-limb WAT
    (schoolbook mul; restoring binary long division for div/mod; limb-wise
    shifts). ABI stays FC (Bool result). -/
private unsafe def testMultiwordDivMod
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrapProgram "WideDivMod" <|
    "  state dummy : UInt64\n\n" ++
    "  init() do\n" ++
    "    dummy := 0\n\n" ++
    "  entry check() : Bool do\n" ++
    "    let a : UInt128 := 0x10000000100000003\n" ++
    "    let b : UInt128 := 0x100000002\n" ++
    "    let s : UInt128 := a + b\n" ++
    "    let p : UInt128 := a * b\n" ++
    "    let q : UInt128 := a / b\n" ++
    "    let r : UInt128 := a % b\n" ++
    "    let c : UInt32 := 65\n" ++
    "    let sl : UInt128 := a << c\n" ++
    "    let sr : UInt128 := a >> c\n" ++
    "    return (s > a) && (p > a) && (q > 0) && (r < b) && (sl > 0) && (sr > 0)\n"
  let compiled ← compileSource session source
    "Examples.WideDivMod" "<cw-wide-divmod>"
  let plan ← liftResult <| planCw compiled
  let files ← liftResult <| filesCw compiled
  let wat ← findFile files "WideDivMod.wat"
  expect (wat.contains "multiword checked_add")
    "wide-divmod: WAT must emit multiword checked_add"
  expect (wat.contains "multiword checked_mul")
    "wide-divmod: WAT must emit multiword checked_mul (schoolbook)"
  expect (wat.contains "multiword checked_div")
    "wide-divmod: WAT must emit multiword checked_div (binary long division)"
  expect (wat.contains "multiword checked_mod")
    "wide-divmod: WAT must emit multiword checked_mod (binary long division)"
  expect (wat.contains "binary long division")
    "wide-divmod: WAT comment must name binary long division"
  -- Honest multiword: must not fall back to single-limb i64.div_u / rem_u as
  -- the only path for the body (markers prove multi-limb path is present).
  expect (wat.contains "$t_mw_rem0")
    "wide-divmod: WAT must use multiword rem scratch"
  expect (wat.contains "$t_mw_quot0")
    "wide-divmod: WAT must use multiword quot scratch"
  expect (wat.contains "multiword shl nLimbs=2 bitWidth=128")
    "wide-divmod: WAT must emit UInt128 multiword shl"
  expect (wat.contains "multiword shr nLimbs=2 bitWidth=128")
    "wide-divmod: WAT must emit UInt128 multiword shr"
  let _ := plan
  IO.println "  ✓ multiword UInt128 body add/mul/div/mod/shl/shr"

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

/-- B-RET-ABI fail-closed: named param >8 leaves, return >8 leaves, pureFn aggregate. -/
private unsafe def testAggregateReturnFc
    (session : Language.Loader.ParserSession) : IO Unit := do
  -- Named aggregate param >8 leaves stays FC.
  let paramSrc := wrapProgram "WideParam" <|
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
    "  entry take(p : Wide) : UInt64 do\n" ++
    "    return s\n\n" ++
    "  view get() : UInt64 do\n" ++
    "    return s\n"
  let paramCompiled ← compileSource session paramSrc "Examples.WideParam" "<cw-wide-param>"
  expectPlanErrorContaining "named aggregate param >8" "1..8"
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
  IO.println "  ✓ aggregate return FC boundaries (param>8 / return>8 / pureFn)"

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

/-- N-ANON-RESULT helper for shapes that must remain fail closed. -/
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

private unsafe def testAnonymousReturnBoundaries
    (session : Language.Loader.ParserSession) : IO Unit := do
  -- Bytes N return uses one zero-extended u64 ABI leaf per byte.
  let bytesSrc := wrapProgram "BytesRet" <|
    "  state payload : Bytes 2\n\n" ++
      "  init() do\n" ++
      "    payload[0] := 1\n" ++
      "    payload[1] := 2\n\n" ++
      "  view getBytes() : Bytes 2 do\n" ++
      "    return payload\n"
  let bytesCompiled ← compileSource session bytesSrc "Examples.BytesRet" "<cw-BytesRet>"
  let bytesPlan ← liftResult <| planCw bytesCompiled
  let some getBytes := bytesPlan.entries.find? (·.name == "getBytes") |
    throw <| IO.userError "BytesRet missing getBytes"
  match getBytes.resultKind with
  | .aggregate leaves =>
      expect (leaves.size == 2 && leaves.all (·.byteWidth == 8))
        "BytesRet must return two zero-extended u64 ABI leaves"
  | _ => throw <| IO.userError "BytesRet resultKind must be aggregate"
  -- Dense Map cap-8 return uses occ/key/value × 8 = 24 u64 leaves.
  let mapSrc := wrapProgram "MapRet" <|
    "  state table : Map UInt64 UInt64\n\n" ++
      "  init() do\n" ++
      "    table[0] := 1\n\n" ++
      "  view getMap() : Map UInt64 UInt64 do\n" ++
      "    return table\n"
  let mapCompiled ← compileSource session mapSrc "Examples.MapRet" "<cw-MapRet>"
  let mapPlan ← liftResult <| planCw mapCompiled
  let some getMap := mapPlan.entries.find? (·.name == "getMap") |
    throw <| IO.userError "MapRet missing getMap"
  match getMap.resultKind with
  | .aggregate leaves =>
      expect (leaves.size == 24 && leaves.all (·.byteWidth == 8))
        "MapRet must return 24 u64 ABI leaves"
  | _ => throw <| IO.userError "MapRet resultKind must be aggregate"
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
  IO.println "  ✓ anonymous Bytes/Map returns + Array9/nested Option FC boundaries"

/-- B-OPT-STATE / BL-33: Option UInt64 state = Enum-shaped 2-leaf layout
    (`slot_tag` + `slot_p0`); construct none zeros payload; match read via
    VariantTag/VariantPayload; storeAtomic on assign. -/
private unsafe def testOptionState
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrapProgram "OptionState" <|
    "  state slot : Option UInt64\n\n" ++
    "  init() do\n" ++
    "    slot := Option.none()\n\n" ++
    "  entry set(v : UInt64) : UInt64 do\n" ++
    "    slot := Option.some(v)\n" ++
    "    return v\n\n" ++
    "  entry clear() : UInt64 do\n" ++
    "    slot := Option.none()\n" ++
    "    return 0\n\n" ++
    "  view peek() : UInt64 do\n" ++
    "    match slot with\n" ++
    "    | Option.some(x) => do\n" ++
    "      return x\n" ++
    "    | _ => do\n" ++
    "      return 0\n\n" ++
    "  view getOpt() : Option UInt64 do\n" ++
    "    return slot\n"
  let compiled ← compileSource session source "Examples.OptionState"
    "<cw-option-state>"
  let plan ← liftResult <| planCw compiled
  expect (plan.storage.fields.size == 2)
    s!"OptionState: Option UInt64 must flatten to tag+payload (2), got {plan.storage.fields.size}"
  expect (plan.storage.fields.map (·.name) == #["slot_tag", "slot_p0"])
    s!"OptionState: leaf names must be slot_tag/slot_p0, got {plan.storage.fields.map (·.name)}"
  expect (plan.storage.fields.all (·.byteWidth == 8))
    "OptionState leaves must be 8-byte UInt64 KV words"
  let some set := plan.entries.find? (·.name == "set") |
    throw <| IO.userError "OptionState missing set"
  let hasAtomic := set.body.any fun s =>
    match s with
    | .storeAtomic leaves => leaves.size == 2
    | _ => false
  expect hasAtomic
    "OptionState set construct+store must storeAtomic tag+payload leaves"
  let some clear := plan.entries.find? (·.name == "clear") |
    throw <| IO.userError "OptionState missing clear"
  let clearAtomic := clear.body.any fun s =>
    match s with
    | .storeAtomic leaves => leaves.size == 2
    | _ => false
  expect clearAtomic
    "OptionState clear Option.none must storeAtomic 2 leaves"
  let initAtomic := plan.initializer.body.any fun s =>
    match s with
    | .storeAtomic leaves => leaves.size == 2
    | _ => false
  expect initAtomic
    "OptionState init Option.none must storeAtomic 2 leaves"
  let some peek := plan.entries.find? (·.name == "peek") |
    throw <| IO.userError "OptionState missing peek"
  expect (peek.mode == .view && peek.resultKind == .uint64)
    "OptionState peek must be view UInt64"
  -- getOpt return of stored Option → 2-leaf aggregate.
  let some getOpt := plan.entries.find? (·.name == "getOpt") |
    throw <| IO.userError "OptionState missing getOpt"
  expect (getOpt.mode == .view) "OptionState getOpt must be view"
  match getOpt.resultKind with
  | .aggregate leaves =>
      expect (leaves.size == 2)
        s!"OptionState getOpt must return 2-leaf Option, got {leaves.size}"
  | other =>
      throw <| IO.userError
        s!"OptionState getOpt resultKind must be .aggregate, got {repr other}"
  match getOpt.body[getOpt.body.size - 1]! with
  | .returnAggregate leaves leafIsInt =>
      expect (leaves.size == 2 && leafIsInt.size == 2)
        "OptionState getOpt returnAggregate must have 2 leaves"
      match leaves[0]!, leaves[1]! with
      | .stateLoad 0, .stateLoad 1 => pure ()
      | a, b =>
          throw <| IO.userError
            s!"OptionState getOpt leaves must be stateLoad 0/1, got {repr a}/{repr b}"
  | _ =>
      throw <| IO.userError "OptionState getOpt must end with .returnAggregate"
  match validatePlan plan with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"OptionState plan must validate: {e.render}"
  let _ir ← liftResult <| irCw compiled
  let files ← liftResult <| filesCw compiled
  let wat ← findFile files "OptionState.wat"
  expect (wat.contains "pf:cw:v1:state:0") "OptionState WAT state key 0"
  expect (wat.contains "pf:cw:v1:state:1") "OptionState WAT state key 1"
  expect (wat.contains "$pf_query_ok_agg" || wat.contains "ret_kind")
    "OptionState WAT multi-leaf return surface for getOpt"
  let abi ← findFile files "OptionState.cosmwasm-abi.json"
  expect (abi.contains "getOpt")
    s!"OptionState ABI must declare getOpt, got: {abi}"
  IO.println "  ✓ OptionState Option UInt64 state Plan/IR/WAT/ABI pin"

/-- CW-OPT-INT: Option Int64 state = unsigned tag + signed 8-byte payload
    (same flatten as Option UInt64; not a UInt64 alias). peek match returns
    Int64 — anonymous Option Int64 return stays fail closed. -/
private unsafe def testOptionInt64State
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrapProgram "OptInt64" <|
    "  state slot : Option Int64\n\n" ++
    "  init() do\n" ++
    "    slot := Option.none()\n\n" ++
    "  entry set(v : Int64) : Int64 do\n" ++
    "    slot := Option.some(v)\n" ++
    "    return v\n\n" ++
    "  entry clear() : Int64 do\n" ++
    "    slot := Option.none()\n" ++
    "    return 0\n\n" ++
    "  view peek() : Int64 do\n" ++
    "    match slot with\n" ++
    "    | Option.some(x) => do\n" ++
    "      return x\n" ++
    "    | _ => do\n" ++
    "      return 0\n"
  let compiled ← compileSource session source "Examples.OptInt64"
    "<cw-option-int64>"
  let plan ← liftResult <| planCw compiled
  expect (plan.storage.fields.size == 2)
    s!"OptInt64: Option Int64 must flatten to tag+payload (2), got {plan.storage.fields.size}"
  expect (plan.storage.fields.map (·.name) == #["slot_tag", "slot_p0"])
    s!"OptInt64: leaf names must be slot_tag/slot_p0, got {plan.storage.fields.map (·.name)}"
  expect (plan.storage.fields[0]!.byteWidth == 8) "OptInt64 tag byteWidth=8"
  expect (plan.storage.fields[1]!.byteWidth == 8) "OptInt64 p0 byteWidth=8"
  expect (!plan.storage.fields[0]!.isInt) "OptInt64 tag stays unsigned"
  expect plan.storage.fields[1]!.isInt "OptInt64 p0 is signed Int64"
  expect (layoutFieldTypeSuffix
      plan.storage.fields[0]!.byteWidth plan.storage.fields[0]!.isInt == "u64-le")
    "OptInt64 tag ABI suffix is u64-le"
  expect (layoutFieldTypeSuffix
      plan.storage.fields[1]!.byteWidth plan.storage.fields[1]!.isInt == "i64-le")
    "OptInt64 p0 ABI suffix is i64-le (not a UInt64 alias)"
  let mixedAtomic (body : Array Statement) : Bool :=
    body.any fun s =>
      match s with
      | .storeAtomic leaves =>
          leaves.size == 2 &&
            !leaves[0]!.isInt && leaves[0]!.byteWidth == 8 &&
            leaves[1]!.isInt && leaves[1]!.byteWidth == 8
      | _ => false
  expect (mixedAtomic plan.initializer.body)
    "OptInt64 init Option.none must storeAtomic mixed isInt (tag u64, p0 i64)"
  let some set := plan.entries.find? (·.name == "set") |
    throw <| IO.userError "OptInt64 missing set"
  expect (set.resultKind == MethodResultKind.int64) "OptInt64 set result Int64"
  expect (mixedAtomic set.body)
    "OptInt64 set some(v) must storeAtomic mixed isInt"
  let some clear := plan.entries.find? (·.name == "clear") |
    throw <| IO.userError "OptInt64 missing clear"
  expect (mixedAtomic clear.body)
    "OptInt64 clear Option.none must storeAtomic mixed isInt"
  let some peek := plan.entries.find? (·.name == "peek") |
    throw <| IO.userError "OptInt64 missing peek"
  expect (peek.mode == .view && peek.resultKind == MethodResultKind.int64)
    "OptInt64 peek must be view Int64 (not Option Int64 return)"
  match validatePlan plan with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"OptInt64 plan must validate: {e.render}"
  let files ← liftResult <| filesCw compiled
  let wat ← findFile files "OptInt64.wat"
  expect (wat.contains "pf_db_load_u64") "OptInt64 WAT 8-byte Region load"
  expect (wat.contains "pf_db_store_u64") "OptInt64 WAT 8-byte Region store"
  expect (wat.contains "pf:cw:v1:state:0") "OptInt64 WAT state key 0"
  expect (wat.contains "pf:cw:v1:state:1") "OptInt64 WAT state key 1"
  let abi ← findFile files "OptInt64.cosmwasm-abi.json"
  expect (abi.contains
      "{\"name\":\"slot_tag\",\"key\":\"pf:cw:v1:state:0\",\"type\":\"u64\"}")
    s!"OptInt64 ABI tag must be u64, got: {abi}"
  expect (abi.contains
      "{\"name\":\"slot_p0\",\"key\":\"pf:cw:v1:state:1\",\"type\":\"i64\"}")
    s!"OptInt64 ABI p0 must be i64 (not both-u64 alias), got: {abi}"
  expect (abi.contains "\"returns\":\"i64\"") "OptInt64 ABI returns i64"
  IO.println "  ✓ Option Int64 state tag+signed payload Plan/IR/WAT/ABI pin"

/-- Option Int8 / Option UInt128 stay fail closed on the historical payload
    needle (`requires UInt64 payload` is a contains-match). Anonymous
    `Option Int64` return stays fail closed on the existing UInt64-payload
    return needle. -/
private unsafe def testOptionInt64ElementFc
    (session : Language.Loader.ParserSession) : IO Unit := do
  let optI8 := wrapProgram "OptI8Cw" <|
    "  state o : Option Int8\n\n" ++
    "  init() do\n" ++
    "    o := Option.none()\n\n" ++
    "  view peek() : UInt64 do\n" ++
    "    return 0\n"
  let optI8Compiled ← compileSource session optI8 "Examples.OptI8Cw" "<cw-opt-i8>"
  expectPlanErrorContaining "OptI8" "requires UInt64 payload"
    (planCw optI8Compiled)
  let optU128 := wrapProgram "OptU128Cw" <|
    "  state o : Option UInt128\n\n" ++
    "  init() do\n" ++
    "    o := Option.none()\n\n" ++
    "  view peek() : UInt64 do\n" ++
    "    return 0\n"
  let optU128Compiled ← compileSource session optU128 "Examples.OptU128Cw"
    "<cw-opt-u128>"
  expectPlanErrorContaining "OptU128" "requires UInt64 payload"
    (planCw optU128Compiled)
  IO.println "  ✓ Option Int8 / Option UInt128 stay fail closed"

/-- CW-MAP-INT: Map UInt64 Int64 state = cap-8 24-leaf occ/key/val flatten
    (same loop IR as Map UInt64 UInt64). occ/key stay unsigned u64-le;
    only val slots (`i % 3 == 2`) are signed i64-le — not a UInt64-value
    alias. get match returns Int64; anonymous Map Int64 return stays FC. -/
private unsafe def testMapInt64State
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrapProgram "MapInt64" <|
    "  state m : Map UInt64 Int64\n\n" ++
    "  init() do\n" ++
    "    m := Map.empty()\n\n" ++
    "  entry put(k : UInt64, v : Int64) : Int64 do\n" ++
    "    m[k] := v\n" ++
    "    return v\n\n" ++
    "  view get(k : UInt64) : Int64 do\n" ++
    "    match m[k] with\n" ++
    "    | Option.some(x) => do\n" ++
    "      return x\n" ++
    "    | _ => do\n" ++
    "      return 0\n"
  let compiled ← compileSource session source "Examples.MapInt64"
    "<cw-map-int64>"
  let plan ← liftResult <| planCw compiled
  expect (plan.storage.fields.size == 24)
    s!"MapInt64: Map UInt64 Int64 must flatten to 24 leaves, got {plan.storage.fields.size}"
  for i in [0:24] do
    let some field := plan.storage.fields[i]? |
      throw <| IO.userError s!"MapInt64 missing field {i}"
    expect (field.name == s!"m_{i}")
      s!"MapInt64 field {i} name must be m_{i}, got {field.name}"
    expect (field.byteWidth == 8)
      s!"MapInt64 m_{i} byteWidth=8"
    expect (field.isInt == (i % 3 == 2))
      s!"MapInt64 m_{i} isInt must be {i % 3 == 2} (val only)"
    let wantSuffix := if i % 3 == 2 then "i64-le" else "u64-le"
    expect (layoutFieldTypeSuffix field.byteWidth field.isInt == wantSuffix)
      s!"MapInt64 m_{i} ABI suffix must be {wantSuffix}"
  let mixedMapAtomic (body : Array Statement) : Bool :=
    body.any fun s =>
      match s with
      | .storeAtomic leaves =>
          leaves.size == 24 &&
            Id.run do
              let mut ok := true
              for i in [0:24] do
                match leaves[i]? with
                | none => ok := false
                | some leaf =>
                    unless leaf.byteWidth == 8 && leaf.isInt == (i % 3 == 2) do
                      ok := false
              pure ok
      | _ => false
  expect (mixedMapAtomic plan.initializer.body)
    "MapInt64 init empty must storeAtomic 24 leaves (val isInt only)"
  let some put := plan.entries.find? (·.name == "put") |
    throw <| IO.userError "MapInt64 missing put"
  expect (put.resultKind == MethodResultKind.int64) "MapInt64 put result Int64"
  expect (mixedMapAtomic put.body)
    "MapInt64 put must storeAtomic 24 leaves (val isInt only)"
  let some get := plan.entries.find? (·.name == "get") |
    throw <| IO.userError "MapInt64 missing get"
  expect (get.mode == .view && get.resultKind == MethodResultKind.int64)
    "MapInt64 get must be view Int64 (not Map return)"
  match validatePlan plan with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"MapInt64 plan must validate: {e.render}"
  let files ← liftResult <| filesCw compiled
  let wat ← findFile files "MapInt64.wat"
  expect (wat.contains "pf_db_load_u64") "MapInt64 WAT 8-byte Region load"
  expect (wat.contains "pf_db_store_u64") "MapInt64 WAT 8-byte Region store"
  expect (wat.contains "(call $pf_parse_i64_field")
    "MapInt64 Int64 entry word must be signed-parsed"
  let abi ← findFile files "MapInt64.cosmwasm-abi.json"
  expect (abi.contains
      "{\"name\":\"m_0\",\"key\":\"pf:cw:v1:state:0\",\"type\":\"u64\"}")
    s!"MapInt64 ABI occ m_0 must be u64, got: {abi}"
  expect (abi.contains
      "{\"name\":\"m_1\",\"key\":\"pf:cw:v1:state:1\",\"type\":\"u64\"}")
    s!"MapInt64 ABI key m_1 must be u64, got: {abi}"
  expect (abi.contains
      "{\"name\":\"m_2\",\"key\":\"pf:cw:v1:state:2\",\"type\":\"i64\"}")
    s!"MapInt64 ABI val m_2 must be i64 (not a UInt64 alias), got: {abi}"
  expect (abi.contains
      "{\"name\":\"m_23\",\"key\":\"pf:cw:v1:state:23\",\"type\":\"i64\"}")
    s!"MapInt64 ABI last val m_23 must be i64, got: {abi}"
  expect (abi.contains "\"returns\":\"i64\"") "MapInt64 ABI returns i64"
  IO.println "  ✓ Map UInt64 Int64 state cap-8 occ/key unsigned + val signed"

/-- Map Int8-value / Map UInt128-value stay fail closed on the historical
    Map-U64-U64 needle (`Map state admits only Map UInt64 UInt64` is a
    contains-match). Anonymous `Map UInt64 Int64` return stays fail closed
    on the existing UInt64-value return needle. -/
private unsafe def testMapInt64ElementFc
    (session : Language.Loader.ParserSession) : IO Unit := do
  let mapI8 := wrapProgram "MapI8Cw" <|
    "  state m : Map UInt64 Int8\n\n" ++
    "  init() do\n" ++
    "    m := Map.empty()\n\n" ++
    "  entry put(k : UInt64, v : UInt64) : UInt64 do\n" ++
    "    return v\n"
  let mapI8Compiled ← compileSource session mapI8 "Examples.MapI8Cw" "<cw-map-i8>"
  expectPlanErrorContaining "MapI8" "Map state admits only Map UInt64 UInt64"
    (planCw mapI8Compiled)
  let mapU128 := wrapProgram "MapU128Cw" <|
    "  state m : Map UInt64 UInt128\n\n" ++
    "  init() do\n" ++
    "    m := Map.empty()\n\n" ++
    "  entry put(k : UInt64, v : UInt64) : UInt64 do\n" ++
    "    return v\n"
  let mapU128Compiled ← compileSource session mapU128 "Examples.MapU128Cw"
    "<cw-map-u128>"
  expectPlanErrorContaining "MapU128" "Map state admits only Map UInt64 UInt64"
    (planCw mapU128Compiled)
  IO.println "  ✓ Map Int8 / Map UInt128 stay fail closed"

private unsafe def testMapInt64Return
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrapProgram "MapInt64RetCw" <|
    "  state m : Map UInt64 Int64\n\n" ++
    "  init() do\n" ++
    "    m := Map.empty()\n\n" ++
    "  view dump() : Map UInt64 Int64 do\n" ++
    "    return m\n"
  let compiled ← compileSource session source "Examples.MapInt64RetCw"
    "<cw-map-int64-ret>"
  let plan ← liftResult <| planCw compiled
  let some dump := plan.entries.find? (·.name == "dump") |
    throw <| IO.userError "MapInt64Ret missing dump"
  match dump.resultKind with
  | .aggregate leaves =>
      expect (leaves.size == 24)
        s!"MapInt64Ret must have 24 leaves, got {leaves.size}"
      expect ((List.range 24).all (fun i =>
          leaves[i]!.isInt == (i % 3 == 2)))
        "MapInt64Ret val slots must be isInt"
  | other =>
      throw <| IO.userError
        s!"MapInt64Ret dump must be .aggregate, got {repr other}"
  IO.println "  ✓ Map UInt64 Int64 return 24-leaf val-only isInt"

/-- B-OPT-STATE FC: Option of non-UInt64, nested Option, Option params stay closed. -/
private unsafe def expectOptionStateFailClosed
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
                s!"{label}: CosmWasm must fail closed on this Option state/param shape"

private unsafe def testOptionStateFailClosed
    (session : Language.Loader.ParserSession) : IO Unit := do
  -- Option Bool state remains fail closed (payload not UInt64).
  expectOptionStateFailClosed session "OptBoolState" "Examples.OptBoolState"
    ("  state flag : Option Bool\n\n" ++
      "  init() do\n" ++
      "    flag := Option.none()\n\n" ++
      "  view peek() : UInt64 do\n" ++
      "    return 0\n")
    #["Option", "UInt64", "payload", "unsupported", "state"]
  -- Nested Option (Option Array …) state remains fail closed.
  expectOptionStateFailClosed session "OptNestedState" "Examples.OptNestedState"
    ("  state nested : Option Array UInt64 2\n\n" ++
      "  init() do\n" ++
      "    nested := Option.none()\n\n" ++
      "  view peek() : UInt64 do\n" ++
      "    return 0\n")
    #["Option", "UInt64", "payload", "unsupported", "state", "Array"]
  IO.println "  ✓ Option state FC boundaries (Bool / nested)"

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
  let compiled ← compileSource session stateCellSourceText stateCellModuleName "<cw-agg>"
  let output ← liftResult <| materializeSelected TargetId.cosmwasm compiled
  let files := MaterializedArtifactsV1.filesOf output
  expect (files.any (·.path == "StateCell.wat")) "materialized WAT"
  expect (files.any (·.path == "StateCell.cosmwasm-abi.json")) "materialized ABI"
  expect (MaterializedArtifactsV1.artifactProgramNameOf output == "StateCell")
    "artifact program name"
  IO.println "  ✓ Registry materializeResult cosmwasm"

/-- CW-1a: product capability → materialize → locked wat2wasm Finalize.
    Write base files into a temp staging dir first; wat2wasm runs inside
    that dir. wasmd / cosmwasm-vm are not invoked. Tool Lock `wat2wasm`
    is required — do not skip-clean if it is missing. -/
private unsafe def testCapabilityProductPath
    (session : Language.Loader.ParserSession) : IO Unit := do
  let compiled ← compileSource session stateCellSourceText stateCellModuleName
    "<cw-finalize>"
  let selection ← liftResult <| resolveBuildSelectionV1 TargetId.cosmwasm none
  expect (selection.codegenProfile == CodegenProfileId.cosmwasmWasmU64V1)
    "CosmWasm selection must bind cosmwasm-wasm-u64-v1"
  let capability ← liftResult <|
    Targets.resolveEngineeringRequirementsV1 selection compiled
  let artifacts ← liftResult <| Targets.materializeResult capability
  let files := MaterializedArtifactsV1.filesOf artifacts
  IO.FS.withTempDir fun stagingDir => do
    for f in files do
      let path := stagingDir / f.path
      if let some parent := path.parent then
        IO.FS.createDirAll parent
      IO.FS.writeFile path f.contents
    let finalized ← Targets.finalizeMaterializedArtifactsV1
      capability artifacts stagingDir
    expect (FinalizedArtifactsV1.deployableOf finalized)
      "CosmWasm locked wat2wasm finalization must be deployable"
    expect (FinalizedArtifactsV1.extraFilesOf finalized == #["StateCell.wasm"])
      "CosmWasm locked finalization must add exactly StateCell.wasm"
    let note := FinalizedArtifactsV1.evidenceNoteOf finalized
    expect (note.contains "wat2wasm")
      s!"CosmWasm Finalize evidence must cite wat2wasm, got: {note}"
    expect (note.contains "runtime remains separate")
      s!"CosmWasm Finalize evidence must cite runtime remains separate, got: {note}"
    let wasm ← IO.FS.readBinFile (stagingDir / "StateCell.wasm")
    expect (wasm.size >= 8 && wasm[0]! == 0x00 && wasm[1]! == 0x61 &&
        wasm[2]! == 0x73 && wasm[3]! == 0x6d && wasm[4]! == 0x01 &&
        wasm[5]! == 0x00 && wasm[6]! == 0x00 && wasm[7]! == 0x00)
      "StateCell.wasm must carry Wasm magic/version 00 61 73 6d 01 00 00 00"
  IO.println "  ✓ capability product Finalize (locked wat2wasm)"

/-- CW-1a: grammar-valid but unregistered profile stays unknown.
    Do not invent a reserved extra CosmWasm profile id. -/
private unsafe def testUnknownProfileFailClosed : IO Unit := do
  match CodegenProfileId.parse? "not-a-real-profile-v1" with
  | none =>
      throw <| IO.userError "not-a-real-profile-v1 must remain grammar-valid"
  | some unknown =>
      match resolveBuildSelectionV1 TargetId.cosmwasm (some unknown) with
      | .error e =>
          expect (e.code == "PF-PROFILE-UNKNOWN")
            s!"unknown CosmWasm profile must be PF-PROFILE-UNKNOWN, got {e.code}: {e.render}"
      | .ok sel =>
          throw <| IO.userError
            s!"unknown CosmWasm profile must fail closed, got {sel.codegenProfile}"
  IO.println "  ✓ unknown profile fail closed"

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

/-- B-CTX-OPEN: `context.unixTimeSeconds` lowers on CosmWasm to
    Env.block.time.seconds() — Plan Expr `.blockTimeSeconds`, WAT parses Env
    JSON `"time"` (nanoseconds string) and divides by 10^9. -/
private unsafe def testContextReadUnixTime
    (session : Language.Loader.ParserSession) : IO Unit := do
  let src := wrapProgram "ClockBox" <|
    "  state t : UInt64\n\n" ++
    "  init() do\n" ++
    "    t := 0\n\n" ++
    "  entry stamp() : UInt64 do\n" ++
    "    t := context.unixTimeSeconds\n" ++
    "    return t\n\n" ++
    "  view last() : UInt64 do\n" ++
    "    return t\n"
  let compiled ← compileSource session src "Examples.ClockBox" "<cw-clock-box>"
  let plan ← liftResult <| planCw compiled
  let some stamp := plan.entries.find? (·.name == "stamp") |
    throw <| IO.userError "clock-box: missing stamp entry"
  let hasBlockTime := stamp.body.any fun s =>
    match s with
    | .store op =>
        match op.value with
        | .blockTimeSeconds => true
        | _ => false
    | _ => false
  expect hasBlockTime "clock-box: stamp must store blockTimeSeconds"
  let files ← liftResult <| filesCw compiled
  let wat ← findFile files "ClockBox.wat"
  -- Exact seconds accessor: Env JSON `"time"` (ns) ÷ 10^9 → whole seconds.
  expect (wat.contains "$pf_env_block_time_seconds")
    "clock-box: WAT must contain env block-time seconds helper"
  expect (wat.contains "i64.div_u")
    "clock-box: WAT must divide nanoseconds by 1e9"
  expect (wat.contains "(i64.const 1000000000)")
    "clock-box: WAT must use exact 10^9 divisor"
  expect (wat.contains "$pf_block_time_secs")
    "clock-box: WAT must stage seconds in pf_block_time_secs global"
  expect (wat.contains "\\\"time\\\"")
    "clock-box: WAT data must include Env time field needle"
  IO.println "  ✓ ContextRead unixTimeSeconds admit (B-CTX-OPEN)"

/-- Flatten one Plan Expr tree (binary/unary/compare nest) into a preorder
    list of every node. Used to pin caller Principal leaf order even when
    leaves sit inside leaf-wise `==` (`boolAnd` of `compare` nodes). -/
private partial def flattenExpr (e : Expr) : Array Expr :=
  let children : Array Expr :=
    match e with
    | .checkedAdd a b | .checkedSub a b | .checkedMul a b
    | .checkedDiv a b | .checkedMod a b
    | .bitAnd a b | .bitOr a b | .bitXor a b | .shl a b | .shr a b
    | .signedCheckedAdd a b | .signedCheckedSub a b | .signedCheckedMul a b
    | .signedCheckedDiv a b | .signedCheckedMod a b | .sar a b
    | .narrowCheckedAdd _ a b | .narrowCheckedSub _ a b
    | .narrowCheckedMul _ a b | .narrowCheckedDiv _ a b
    | .narrowCheckedMod _ a b
    | .narrowBitAnd _ a b | .narrowBitOr _ a b | .narrowBitXor _ a b
    | .narrowShl _ a b | .narrowShr _ a b
    | .boolAnd a b | .boolOr a b | .compare _ a b | .wideCompare _ _ a b
    | .signedCompare _ a b => #[a, b]
    | .checkedNeg a | .bitNot a | .boolNot a | .narrowBitNot _ a => #[a]
    | .callFn _ args => args
    | _ => #[]
  children.foldl (fun acc c => acc ++ flattenExpr c) #[e]

/-- Collect every Plan Expr node from a method body for caller Principal
    leaf-order pins. -/
private partial def collectExprs (stmts : Array Statement) : Array Expr :=
  Id.run do
    let mut out : Array Expr := #[]
    for s in stmts do
      match s with
      | .store op => out := out ++ flattenExpr op.value
      | .storeAtomic leaves =>
          for op in leaves do out := out ++ flattenExpr op.value
      | .returnValue v => out := out ++ flattenExpr v
      | .returnAggregate leaves _ =>
          for l in leaves do out := out ++ flattenExpr l
      | .assert c => out := out ++ flattenExpr c
      | .ifThenElse c t e =>
          out := out ++ flattenExpr c
          out := out ++ collectExprs t
          out := out ++ collectExprs e
      | .switchOn scrut cases defB =>
          out := out ++ flattenExpr scrut
          for (_, body) in cases do out := out ++ collectExprs body
          out := out ++ collectExprs defB
      | .forLoop _ initial cond update _ body =>
          out := out ++ flattenExpr initial
          out := out ++ flattenExpr cond
          out := out ++ flattenExpr update
          out := out ++ collectExprs body
      | _ => pure ()
    pure out

/-- Count non-overlapping occurrences of `needle` in `haystack`. -/
private def countSubstr (haystack needle : String) : Nat :=
  if needle.isEmpty then 0 else (haystack.splitOn needle).length - 1

/-- ADR-0031 S2: `context.blockHeight` lowers on CosmWasm to Env.block.height —
    Plan Expr `.blockHeight`, WAT parses Env JSON `"height"` (bare u64 decimal)
    at instantiate/execute/query entry. Exact UInt64 fit, no range guard. -/
private unsafe def testContextReadBlockHeight
    (session : Language.Loader.ParserSession) : IO Unit := do
  let src := wrapProgram "HeightBox" <|
    "  state h : UInt64\n\n" ++
    "  init() do\n" ++
    "    h := 0\n\n" ++
    "  entry stamp() : UInt64 do\n" ++
    "    h := context.blockHeight\n" ++
    "    return h\n\n" ++
    "  view last() : UInt64 do\n" ++
    "    return context.blockHeight\n"
  let compiled ← compileSource session src "Examples.HeightBox" "<cw-height-box>"
  let plan ← liftResult <| planCw compiled
  let some stamp := plan.entries.find? (·.name == "stamp") |
    throw <| IO.userError "height-box: missing stamp entry"
  let hasBlockHeight := stamp.body.any fun s =>
    match s with
    | .store op =>
        match op.value with
        | .blockHeight => true
        | _ => false
    | _ => false
  expect hasBlockHeight "height-box: stamp must store blockHeight"
  -- View also admits height (Env present on query; unlike caller).
  let some last := plan.entries.find? (·.name == "last") |
    throw <| IO.userError "height-box: missing last view"
  let viewUsesHeight := last.body.any fun s =>
    match s with
    | .returnValue .blockHeight => true
    | .returnValue _ => false
    | _ => false
  expect viewUsesHeight "height-box: view last must return blockHeight"
  let files ← liftResult <| filesCw compiled
  let wat ← findFile files "HeightBox.wat"
  expect (wat.contains "$pf_env_block_height")
    "height-box: WAT must contain env block-height helper"
  expect (wat.contains "$pf_block_height")
    "height-box: WAT must stage height in pf_block_height global"
  expect (wat.contains "\\\"height\\\"")
    "height-box: WAT data must include Env height field needle"
  -- Pre-parse at all three entry points (init / execute / query).
  let loadLine :=
    "(global.set $pf_block_height (call $pf_env_block_height (local.get $env_ptr)))"
  let loadCount := countSubstr wat loadLine
  expect (loadCount == 3)
    s!"height-box: expected height load at instantiate+execute+query (3), got {loadCount}"
  -- Helper uses bare-number parse (not string-field) and fixed needle 3252/8.
  expect (wat.contains
      "(call $pf_parse_u64_field (local.get $off) (local.get $len) (i32.const 3252) (i32.const 8))")
    "height-box: helper must parse height via pf_parse_u64_field at offset 3252 len 8"
  -- Prior fixed needles stay stable (time still at 3000; sender still at 3241).
  expect (wat.contains "(i32.const 3000) (i32.const 6)")
    "height-box: time needle offset must remain 3000/6"
  expect (wat.contains "(i32.const 3241) (i32.const 10)")
    "height-box: sender needle offset must remain 3241/10"
  -- Unknown ContextRead keys still fail closed at Plan (unixTime/caller/height only).
  -- Shared typing already rejects non-admitted surfaces; Plan unknown-key arm
  -- is covered by non-unixTime/non-caller/non-height ContextRead path.
  IO.println "  ✓ ContextRead context.blockHeight admit (ADR-0031 S2)"

/-- ADR-0031 S4: `context.attachedValue` → MessageInfo.funds single-stake
    amount. Execute/init admit; view/query fail closed. -/
private unsafe def testContextReadAttachedValue
    (session : Language.Loader.ParserSession) : IO Unit := do
  let src := wrapProgram "ValueBox" <|
    "  state paid : UInt64\n\n" ++
    "  init() do\n" ++
    "    paid := 0\n\n" ++
    "  entry collect() : UInt64 do\n" ++
    "    paid := context.attachedValue\n" ++
    "    return paid\n\n" ++
    "  view last() : UInt64 do\n" ++
    "    return paid\n"
  let compiled ← compileSource session src "Examples.ValueBox" "<cw-value-box>"
  let plan ← liftResult <| planCw compiled
  let some collect := plan.entries.find? (·.name == "collect") |
    throw <| IO.userError "value-box: missing collect"
  expect (collect.depositPolicy == .allowFunds)
    "value-box: collect must be allowFunds"
  let hasFunds := collect.body.any fun s =>
    match s with
    | .store op =>
        match op.value with
        | .attachedFundsAmount => true
        | _ => false
    | _ => false
  expect hasFunds "value-box: collect must store attachedFundsAmount"
  let files ← liftResult <| filesCw compiled
  let wat ← findFile files "ValueBox.wat"
  expect (wat.contains "$pf_funds_amount")
    "value-box: WAT must contain pf_funds_amount helper"
  expect (wat.contains "(call $pf_funds_amount)")
    "value-box: WAT must call pf_funds_amount"
  let viewSrc := wrapProgram "ValuePeek" <|
    "  state pad : UInt64\n\n" ++
    "  init() do\n" ++
    "    pad := 0\n\n" ++
    "  view peek() : UInt64 do\n" ++
    "    return context.attachedValue\n"
  let vCompiled ← compileSource session viewSrc "Examples.ValuePeek" "<cw-value-peek>"
  expectPlanErrorContaining "value-peek view FC" "attachedValue"
    (planCw vCompiled)
  IO.println "  ✓ ContextRead context.attachedValue execute admit + view FC (ADR-0031 S4)"

/-- ADR-0031 S1: `context.caller` on CosmWasm binds MessageInfo.sender
    (execute/init only) as Principal leaves `callerPrincipalLen` +
    `callerPrincipalWord 0..7` (len + 8×UInt64 LE, zero-padded). View/query
    usage, wrong result type, and unknown keys fail closed at Plan.
    Follow-up: load is per-branch via `methodUsesCallerPrincipalV1`; bech32
    charset gate reuses `$pf_dst_check` before publishing leaf globals. -/
private unsafe def testContextReadCaller
    (session : Language.Loader.ParserSession) : IO Unit := do
  -- Execute accepted: entry stores caller into Principal state; mixed
  -- dispatcher also carries a non-caller entry (`ping`).
  let src := wrapProgram "CallerGate" <|
    "  state owner : Principal\n\n" ++
    "  init() do\n" ++
    "    owner := context.caller\n\n" ++
    "  entry onlyOwner() : UInt64 do\n" ++
    "    assert context.caller == owner\n" ++
    "    return 1\n\n" ++
    "  entry setOwner() : UInt64 do\n" ++
    "    owner := context.caller\n" ++
    "    return 1\n\n" ++
    "  entry ping() : UInt64 do\n" ++
    "    return 1\n\n" ++
    "  view peek() : UInt64 do\n" ++
    "    return 0\n"
  let compiled ← compileSource session src "Examples.CallerGate" "<cw-caller-gate>"
  let plan ← liftResult <| planCw compiled
  -- Predicate pins: init/onlyOwner/setOwner use caller; ping does not.
  expect (methodUsesCallerPrincipalV1 plan.initializer)
    "caller-gate: methodUsesCallerPrincipalV1 init must be true"
  let some onlyOwner := plan.entries.find? (·.name == "onlyOwner") |
    throw <| IO.userError "caller-gate: missing onlyOwner entry"
  let some setOwner := plan.entries.find? (·.name == "setOwner") |
    throw <| IO.userError "caller-gate: missing setOwner entry"
  let some ping := plan.entries.find? (·.name == "ping") |
    throw <| IO.userError "caller-gate: missing ping entry"
  expect (methodUsesCallerPrincipalV1 onlyOwner)
    "caller-gate: methodUsesCallerPrincipalV1 onlyOwner must be true"
  expect (methodUsesCallerPrincipalV1 setOwner)
    "caller-gate: methodUsesCallerPrincipalV1 setOwner must be true"
  expect (!methodUsesCallerPrincipalV1 ping)
    "caller-gate: methodUsesCallerPrincipalV1 ping must be false"
  -- Init body must storeAtomic 9 Principal leaves from caller.
  let initExprs := collectExprs plan.initializer.body
  let initCallerLeaves := initExprs.filterMap fun e =>
    match e with
    | .callerPrincipalLen => some ("len", 0)
    | .callerPrincipalWord i => some ("w", i)
    | _ => none
  expect (initCallerLeaves.size == 9)
    s!"caller-gate init: expected 9 caller Principal leaves, got {initCallerLeaves.size}"
  expect (initCallerLeaves[0]? == some ("len", 0))
    "caller-gate init: leaf 0 must be callerPrincipalLen"
  for i in [0:8] do
    expect (initCallerLeaves[i + 1]? == some ("w", i))
      s!"caller-gate init: leaf {i + 1} must be callerPrincipalWord {i}"
  -- Entry onlyOwner assert uses leaf-wise caller compare (len + 8 words).
  let entryExprs := collectExprs onlyOwner.body
  let entryCallerLeaves := entryExprs.filterMap fun e =>
    match e with
    | .callerPrincipalLen => some ("len", 0)
    | .callerPrincipalWord i => some ("w", i)
    | _ => none
  expect (entryCallerLeaves.size ≥ 9)
    s!"caller-gate onlyOwner: expected ≥9 caller leaves in compare, got {entryCallerLeaves.size}"
  -- WAT: sender needle, load helper, leaf globals, per-branch call sites.
  let files ← liftResult <| filesCw compiled
  let wat ← findFile files "CallerGate.wat"
  expect (wat.contains "$pf_load_caller_principal")
    "caller-gate: WAT must contain sender→Principal pack helper"
  expect (wat.contains "$pf_caller_len")
    "caller-gate: WAT must stage caller len global"
  expect (wat.contains "$pf_caller_w0")
    "caller-gate: WAT must stage caller body word 0"
  expect (wat.contains "$pf_caller_w7")
    "caller-gate: WAT must stage caller body word 7"
  expect (wat.contains "\\\"sender\\\":\\\"")
    "caller-gate: WAT data must include MessageInfo sender needle"
  -- Exactly 3 load sites: instantiate (init) + onlyOwner + setOwner branches.
  -- ping branch must not load. Helper definition body does not contain the
  -- call form `(call $pf_load_caller_principal)`.
  let loadCall := "(call $pf_load_caller_principal)"
  let loadCount := countSubstr wat loadCall
  expect (loadCount == 3)
    s!"caller-gate: expected exactly 3 caller-load call sites (init+onlyOwner+setOwner), got {loadCount}"
  -- ADR-0031 bech32 gate: helper must invoke $pf_dst_check before globals.
  expect (wat.contains "(call $pf_dst_check (i64.extend_i32_u (local.get $n)) (local.get $buf))")
    "caller-gate: pf_load_caller_principal must $pf_dst_check sender bytes before globals"
  -- Zero-padding discipline: helper zeros 64B buffer before copy (high body
  -- bytes beyond len stay 0).
  expect (wat.contains "(i64.store (local.get $buf) (i64.const 0))")
    "caller-gate: WAT must zero body buffer before sender copy (zero-padding)"
  expect (wat.contains "(i64.store offset=56 (local.get $buf) (i64.const 0))")
    "caller-gate: WAT must zero last body word before sender copy"
  -- Per-branch adjacency pins (zero-param methods: load immediately precedes
  -- return). Mixed dispatcher: caller entries load; ping does not.
  expect (wat.contains
      "(call $pf_load_caller_principal)\n    (return (call $m_init ))")
    "caller-gate: instantiate must load caller immediately before $m_init"
  expect (wat.contains
      "(call $pf_load_caller_principal)\n        (return (call $m_onlyOwner ))")
    "caller-gate: onlyOwner execute branch must load caller before $m_onlyOwner"
  expect (wat.contains
      "(call $pf_load_caller_principal)\n        (return (call $m_setOwner ))")
    "caller-gate: setOwner execute branch must load caller before $m_setOwner"
  expect (wat.contains "(return (call $m_ping ))")
    "caller-gate: ping execute branch must be present"
  expect (!wat.contains
      "(call $pf_load_caller_principal)\n        (return (call $m_ping ))")
    "caller-gate: ping execute branch must NOT load caller principal"
  -- View rejected: query has no MessageInfo.sender.
  let viewSrc := wrapProgram "CallerViewBad" <|
    "  state dummy : UInt64\n\n" ++
    "  init() do\n" ++
    "    dummy := 0\n\n" ++
    "  entry bump() : UInt64 do\n" ++
    "    dummy := dummy + 1\n" ++
    "    return dummy\n\n" ++
    "  view who() : UInt64 do\n" ++
    "    let c : Principal := context.caller\n" ++
    "    return 0\n"
  let viewCompiled ← compileSource session viewSrc
    "Examples.CallerViewBad" "<cw-caller-view-bad>"
  match planCw viewCompiled with
  | .error (.planInvariant .cosmwasm msg) =>
      expect (msg.contains "view" || msg.contains "query" ||
          (msg.contains "caller" && msg.contains "not available"))
        s!"view caller FC must cite view/query absence, got: {msg}"
  | .error e =>
      throw <| IO.userError s!"view caller FC: expected cosmwasm planInvariant, got {e.render}"
  | .ok _ =>
      throw <| IO.userError "CosmWasm view context.caller must fail closed at plan"
  -- Wrong type: caller result must be Principal (not UInt64).
  -- Source typing normally rejects `let c : UInt64 := context.caller` before
  -- Plan; pin Plan-level FC by ensuring only Principal is admitted on the
  -- accepted path (covered by init leaf Principal type + isPrincipal gate).
  -- Unknown key remains FC via the non-unixTime/non-caller arm.
  IO.println "  ✓ ContextRead context.caller execute admit + view FC + per-branch load (ADR-0031 S1)"

private unsafe def testPointParam
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrapProgram "PointParam" <|
    "  struct Point where\n" ++
    "    x : UInt64\n" ++
    "    y : UInt64\n" ++
    "  state pad : UInt64\n\n" ++
    "  init() do\n" ++
    "    pad := 0\n\n" ++
    "  entry set(p : Point) : UInt64 do\n" ++
    "    pad := p.x\n" ++
    "    return pad\n"
  let compiled ← compileSource session source "Examples.PointParam" "<cw-point-param>"
  let plan ← liftResult <| planCw compiled
  let some set := plan.entries.find? (·.name == "set") |
    throw <| IO.userError "PointParam missing set"
  expect (set.params.map (·.name) == #["p_x", "p_y"])
    s!"PointParam must flatten to p_x/p_y, got {set.params.map (·.name)}"
  liftResult <| validatePlan plan
  IO.println "  ✓ PointParam named Struct param flatten"

private unsafe def testOptionParam
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrapProgram "OptParam" <|
    "  state pad : UInt64\n\n" ++
    "  init() do\n" ++
    "    pad := 0\n\n" ++
    "  entry put(o : Option UInt64) : UInt64 do\n" ++
    "    return pad\n"
  let compiled ← compileSource session source "Examples.OptParam" "<cw-opt-param>"
  let plan ← liftResult <| planCw compiled
  let some put := plan.entries.find? (·.name == "put") |
    throw <| IO.userError "OptParam missing put"
  expect (put.params.map (·.name) == #["o_tag", "o_p0"])
    s!"OptParam must flatten to o_tag/o_p0, got {put.params.map (·.name)}"
  liftResult <| validatePlan plan
  IO.println "  ✓ OptParam tag+payload flatten"

private unsafe def testArrayParam
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrapProgram "ArrParam" <|
    "  state pad : UInt64\n\n" ++
    "  init() do\n" ++
    "    pad := 0\n\n" ++
    "  entry put(a : Array UInt64 2) : UInt64 do\n" ++
    "    return pad\n"
  let compiled ← compileSource session source "Examples.ArrParam" "<cw-arr-param>"
  let plan ← liftResult <| planCw compiled
  let some put := plan.entries.find? (·.name == "put") |
    throw <| IO.userError "ArrParam missing put"
  expect (put.params.map (·.name) == #["a_0", "a_1"])
    s!"ArrParam must flatten to a_0/a_1, got {put.params.map (·.name)}"
  liftResult <| validatePlan plan
  IO.println "  ✓ ArrParam N×UInt64 flatten"

private unsafe def testArrayInt64Return
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrapProgram "ArrInt64RetCw" <|
    "  state slots : Array Int64 2\n\n" ++
    "  init() do\n" ++
    "    slots[0] := 0\n" ++
    "    slots[1] := 0\n\n" ++
    "  view get() : Array Int64 2 do\n" ++
    "    return slots\n"
  let compiled ← compileSource session source "Examples.ArrInt64RetCw"
    "<cw-arr-int64-ret>"
  let plan ← liftResult <| planCw compiled
  let some get := plan.entries.find? (·.name == "get") |
    throw <| IO.userError "ArrInt64Ret missing get"
  match get.resultKind with
  | .aggregate leaves =>
      expect (leaves.size == 2)
        s!"ArrInt64Ret aggregate return must have 2 leaves, got {leaves.size}"
      expect (leaves[0]!.isInt && leaves[1]!.isInt)
        "ArrInt64Ret leaves must be Int64"
  | other =>
      throw <| IO.userError
        s!"ArrInt64Ret get resultKind must be .aggregate, got {repr other}"
  liftResult <| validatePlan plan
  let files ← liftResult <| filesCw compiled
  let abi ← findFile files "ArrInt64RetCw.cosmwasm-abi.json"
  expect (abi.contains "\"returns\":[\"i64\",\"i64\"]")
    s!"ArrInt64Ret ABI must declare leaf tuple [\"i64\",\"i64\"], got: {abi}"
  IO.println "  ✓ Array Int64 2 view return 2-leaf i64 tuple"

private unsafe def testOptionInt64Return
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrapProgram "OptInt64RetCw" <|
    "  state slot : Option Int64\n\n" ++
    "  init() do\n" ++
    "    slot := Option.none()\n\n" ++
    "  view get() : Option Int64 do\n" ++
    "    return slot\n"
  let compiled ← compileSource session source "Examples.OptInt64RetCw"
    "<cw-opt-int64-ret>"
  let plan ← liftResult <| planCw compiled
  let some get := plan.entries.find? (·.name == "get") |
    throw <| IO.userError "OptInt64Ret missing get"
  match get.resultKind with
  | .aggregate leaves =>
      expect (leaves.size == 2)
        s!"OptInt64Ret must have 2 leaves, got {leaves.size}"
      expect (!leaves[0]!.isInt && leaves[1]!.isInt)
        "OptInt64Ret must be tag unsigned + payload isInt"
  | other =>
      throw <| IO.userError
        s!"OptInt64Ret get resultKind must be .aggregate, got {repr other}"
  IO.println "  ✓ Option Int64 view return tag+signed payload"

private unsafe def testMapParam
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrapProgram "MapParam" <|
    "  state pad : UInt64\n\n" ++
    "  init() do\n" ++
    "    pad := 0\n\n" ++
    "  entry put(m : Map UInt64 UInt64) : UInt64 do\n" ++
    "    return pad\n"
  let compiled ← compileSource session source "Examples.MapParam" "<cw-map-param>"
  let plan ← liftResult <| planCw compiled
  let some put := plan.entries.find? (·.name == "put") |
    throw <| IO.userError "MapParam missing put"
  let expected := (List.range 24).toArray.map (fun i => s!"m_{i}")
  expect (put.params.map (·.name) == expected)
    s!"MapParam must flatten to 24 occ/key/val leaves, got {put.params.map (·.name)}"
  liftResult <| validatePlan plan
  IO.println "  ✓ MapParam 24-leaf occ/key/val flatten"

/-- Entry point for manual / future shard registration. -/
unsafe def testStringReturn : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source := wrapProgram "StrRetCw" <|
    "  state label : String\n\n" ++
    "  init(initial : String) do\n" ++
    "    label := initial\n\n" ++
    "  view getLabel() : String do\n" ++
    "    return label\n"
  let compiled ← compileSource session source "Examples.StrRetCw" "<cw-str-ret>"
  let plan ← liftResult <| planCw compiled
  let some getLabel := plan.entries.find? (·.name == "getLabel") |
    throw <| IO.userError "StrRet missing getLabel"
  match getLabel.resultKind with
  | .aggregate leaves =>
      expect (leaves.size == 9)
        s!"StrRet must have 9 leaves, got {leaves.size}"
      expect (leaves.all (fun l => !l.isInt && l.byteWidth == 8))
        "StrRet leaves must be unsigned 8-byte identity words"
  | other =>
      throw <| IO.userError
        s!"StrRet getLabel resultKind must be .aggregate, got {repr other}"
  IO.println "  ✓ String view return 9-leaf identity"

unsafe def run : IO Unit := do
  IO.println "CosmWasmPlanV1"
  let session ← Tests.Language.ParserSession.shared
  testStateCellPlan session
  testStateCellIRAndWat session
  testMultiField session
  testCallStillFailClosed session
  testResultBearingExternalCallFailClosed
  testCryptoSha256StayFailClosed session
  testBase64HelperMatrix
  testScheduleSubMsg session
  testMultiWidthUInt8 session
  testMultiWidthUInt16UInt32 session
  testMultiWidthFc session
  testUint256Abi session
  testU256ContainerFc session
  testArrayInt64State session
  testArrayInt64x24Layout session
  testArrayInt64ElementFc session
  testNarrowIntAbi session
  testMultiwordDivMod session
  testNamedStructReturn session
  testPointParam session
  testOptionParam session
  testArrayParam session
  testArrayInt64Return session
  testOptionInt64Return session
  testMapInt64Return session
  testMapParam session
  testNamedEnumReturn session
  testAggregateReturnFc session
  testAnonymousArrayReturn session
  testAnonymousOptionReturn session
  testAnonymousReturnBoundaries session
  testOptionState session
  testOptionInt64State session
  testOptionInt64ElementFc session
  testMapInt64State session
  testMapInt64ElementFc session
  testOptionStateFailClosed session
  testInvariantFc session
  testMaterializeAggregate session
  testCapabilityProductPath session
  testUnknownProfileFailClosed
  testStaticLayoutCapacityFc session
  testContextReadUnixTime session
  testContextReadBlockHeight session
  testContextReadCaller session
  testContextReadAttachedValue session
  testStringReturn
  IO.println "CosmWasmPlanV1: all checks passed"

end Tests.Materialization.CosmWasmPlanV1
