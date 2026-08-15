/-
  Ton Plan/IR/Tolk engineering suite (TON-2 StateCell leaf + BL-1 schedule +
  BL-10 named aggregate view returns + BL-23 anonymous Array/Option view
  returns + BL-34 / B-OPT-STATE Option UInt64 state + BL-38 / B-CTX-OPEN
  unixTimeSeconds → Tolk blockchain.now()).

  Pins StateCell plan shape, Tolk surface (Storage/onInternalMessage/get fun),
  op+query_id envelope, UInt64 range-check markers, schedule→createMessage
  out-message emission (dest hash stub / NoBounce / value=0 /
  PAY_FEES_SEPARATELY / op32·query_id·args body), BL-14 multi-width
  UInt{8,16,32} body/state/param (narrow guards + exact cell/param widths),
  B-RET-ABI named Struct/Enum view multi-stack returns, N-ANON-RESULT
  anonymous Array UInt64 N / Option UInt64 view returns (entry aggregate FC),
  B-OPT-STATE Option UInt64 state (Enum-shaped 2-leaf c4 layout, none default,
  payload zeroing, match read, tolk→fif), B-CTX-OPEN context.unixTimeSeconds
  → Plan blockUnixTimeSeconds / Tolk blockchain.now() (entry+view;
  caller/unknown FC), and explicit fail-closed boundaries (sync call,
  UInt128/256, Map/Bytes returns, N>8, nested/narrow-element containers,
  Option non-UInt64 / Option params, invariants, Field/Principal).

  Registered in Tests/Shards/Targets. Not @ton/sandbox runtime (TON-3).
  Not formal D4.
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

private unsafe def testStateCellPlan
    (session : Language.Loader.ParserSession) : IO Unit := do
  let compiled ← compileSource session stateCellSourceText stateCellModuleName "<ton-stateCell>"
  let plan ← liftResult <| planTon compiled
  expect (plan.programName == "StateCell") "program name StateCell"
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
  IO.println "  ✓ StateCell plan shape"

private unsafe def testStateCellIRAndTolk
    (session : Language.Loader.ParserSession) : IO Unit := do
  let compiled ← compileSource session stateCellSourceText stateCellModuleName "<ton-stateCell-ir>"
  let ir ← liftResult <| irTon compiled
  expect (ir.name == "StateCell") "IR name"
  expect (ir.methods.size == 3) "init + 2 entries"
  expect (ir.imports == canonicalImports) "IR host imports"
  let files ← liftResult <| filesTon compiled
  let tolk ← findFile files "StateCell.tolk"
  let abi ← findFile files "StateCell.ton-abi.json"
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
  IO.println "  ✓ StateCell IR/Tolk/ABI shape"

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

private unsafe def testCallSyncFc
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
  IO.println "  ✓ call/sync fail closed"

/-- Value-position Oracle.feed is a distinct envelope gate from the void
    statement pin above. Product resolve must decline
    effect.synchronous-call; the engineering path names the result-bearing
    form. Do not silently accept a minted capability (CW C2 pattern). -/
unsafe def testResultBearingExternalCallFailClosed : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let src := wrapProgram "CallRetTon" <|
    "  state s : UInt64\n\n" ++
    "  init(x : UInt64) do\n" ++
    "    s := x\n\n" ++
    "  entry go() : UInt64 do\n" ++
    "    let y : UInt64 := call Oracle.feed(s)\n" ++
    "    return s\n\n" ++
    "  view peek() : UInt64 do\n" ++
    "    return s\n"
  let validated ← liftResult (← session.selectProgramV1 src
    "<ton-call-ret>" "Examples.CallRetTon" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 validated
  let selection ← liftResult <| resolveBuildSelectionV1 TargetId.ton none
  match Targets.resolveEngineeringRequirementsV1 selection compiled with
  | .error e =>
      expect ((e.render).contains "effect.synchronous-call")
        s!"product resolve must cite effect.synchronous-call, got {e.render}"
  | .ok _ =>
      throw <| IO.userError
        "TON-CALL-RET-FC STOP: product resolve unexpectedly minted a capability; TON must decline effect.synchronous-call (do not switch to the CW C2 pattern)"
  match engineeringPlanFromCompiled compiled with
  | .error e =>
      expect (e.render.contains
          "result-bearing ExternalCall is outside the Ton envelope")
        s!"result-bearing must fail at the named envelope gate, got: {e.render}"
  | .ok _ =>
      throw <| IO.userError
        "result-bearing Oracle.feed must fail closed at Ton engineering Plan"

/-- SYS-S5: TON has no sha256 host. Exact `pf.crypto.sha256` and sibling
    QNs stay Plan fail closed (no hashed / string_hash fallback). -/
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
          s!"{programName} must Plan fail closed (no Ton crypto host)"
  -- TON type policy rejects UInt256 before ExternalCall, so keep the
  -- fixture on admitted UInt64. The needle is still the crypto QN —
  -- not a hashed / string_hash fallback and not the generic call FC.
  expectPlanFc "Sha256Ton" "<ton-sha256>" "Examples.Sha256Ton"
    ("  state pad : UInt64\n\n" ++
      "  init() do\n" ++
      "    pad := 0\n\n" ++
      "  entry probe() : UInt64 do\n" ++
      "    let w : UInt64 := 0\n" ++
      "    let h : UInt64 := call pf.crypto.sha256(w)\n" ++
      "    return pad\n\n" ++
      "  view get() : UInt64 do\n" ++
      "    return pad\n")
    "has no Ton host binding"
  expectPlanFc "Sha256TonHashNoPad" "<ton-sha256-hashnopad>"
    "Examples.Sha256TonHashNoPad"
    ("  state pad : UInt64\n\n" ++
      "  init() do\n" ++
      "    pad := 0\n\n" ++
      "  entry probe() : UInt64 do\n" ++
      "    let w : UInt64 := 0\n" ++
      "    let h : UInt64 := call pf.crypto.hashNoPad(w)\n" ++
      "    return pad\n\n" ++
      "  view get() : UInt64 do\n" ++
      "    return pad\n")
    "has no Ton host binding"
  expectPlanFc "Keccak256Ton" "<ton-keccak256>" "Examples.Keccak256Ton"
    ("  state pad : UInt64\n\n" ++
      "  init() do\n" ++
      "    pad := 0\n\n" ++
      "  entry probe() : UInt64 do\n" ++
      "    let w : UInt64 := 0\n" ++
      "    let h : UInt64 := call pf.crypto.keccak256(w)\n" ++
      "    return pad\n\n" ++
      "  view get() : UInt64 do\n" ++
      "    return pad\n")
    "has no Ton host binding"
  -- SYS-S5-ECDSA-FC-REST: keep admitted UInt64 ABI so the needle is the QN arm.
  expectPlanFc "EcdsaRecoverTon" "<ton-ecdsa-recover>"
    "Examples.EcdsaRecoverTon"
    ("  state pad : UInt64\n\n" ++
      "  init() do\n" ++
      "    pad := 0\n\n" ++
      "  entry probe() : UInt64 do\n" ++
      "    let h : UInt64 := 0\n" ++
      "    let v : UInt64 := 0\n" ++
      "    let r : UInt64 := 0\n" ++
      "    let s : UInt64 := 0\n" ++
      "    let a : UInt64 := call pf.crypto.ecdsaRecoverSecp256k1(h, v, r, s)\n" ++
      "    return pad\n\n" ++
      "  view get() : UInt64 do\n" ++
      "    return pad\n")
    "has no Ton host binding"
    "ecdsaRecoverSecp256k1"
  IO.println "  ✓ pf.crypto.sha256/keccak256 stay fail closed (no Ton host)"

/-- Schedule → Plan/IR/Tolk createMessage pins (destination hash stub, bounce,
    send mode, value=0, op encoding). Sync call remains FC (above). -/
private unsafe def testSchedulePlanAndTolk
    (session : Language.Loader.ParserSession) : IO Unit := do
  -- Receiver stub grammar is lowercase-only (same pilot as NEAR/CosmWasm).
  let schedSrc := wrapProgram "SchedOpen" <|
    "  state s : UInt64\n\n" ++
    "  init(x : UInt64) do\n" ++
    "    s := x\n\n" ++
    "  entry go() : UInt64 do\n" ++
    "    schedule ledger.daily(s)\n" ++
    "    return s\n\n" ++
    "  view peek() : UInt64 do\n" ++
    "    return s\n"
  let compiled ← compileSource session schedSrc "Examples.SchedOpen" "<ton-sched-open>"
  let plan ← liftResult <| planTon compiled
  -- Plan body carries promiseAccount on entry `go`
  let some go := plan.entries.find? (·.name == "go") |
    throw <| IO.userError "missing entry go"
  let hasPromise := go.body.any fun s =>
    match s with
    | .promiseAccount receiver method args =>
        receiver == "ledger" && method == "daily" && args.size == 1
    | _ => false
  expect hasPromise "entry go lowers schedule → promiseAccount(ledger, daily, [s])"
  expect (planUsesPromiseV1 plan) "planUsesPromiseV1 true when schedule present"
  -- Deterministic destination hash + method op (Solana/EVM-class stubs)
  let destHex := scheduleDestHashHexV1 "ledger"
  let methodOp := scheduleMethodOpCodeV1 "daily"
  expect (destHex.length == 64) "dest hash is 64 hex chars"
  expect (destHex ==
      "fe14010b4fe83303852f0467c919ef9a7ca089b91e96e3aad7d426dd87079297")
    "dest hash = SHA-256(UTF-8 \"ledger\") exact pin"
  -- IR carries promiseAccount with same dest hash / op
  let ir ← liftResult <| irTon compiled
  let some goIR := ir.methods.find? (·.name == "go") |
    throw <| IO.userError "missing IR method go"
  let hasPromiseOp := goIR.operations.any fun op =>
    match op with
    | .promiseAccount receiver dest method opCode args =>
        receiver == "ledger" && dest == destHex && method == "daily" &&
          opCode == methodOp && args.size == 1
    | _ => false
  expect hasPromiseOp "IR promiseAccount carries dest hash + method op + 1 arg"
  -- Tolk surface: createMessage + NoBounce + value 0 + PAY_FEES_SEPARATELY + dest stub
  let files ← liftResult <| filesTon compiled
  let tolk ← findFile files "SchedOpen.tolk"
  expect (tolk.contains "createMessage({") "tolk createMessage"
  expect (tolk.contains "bounce: BounceMode.NoBounce") "tolk BounceMode.NoBounce"
  expect (tolk.contains "value: 0") "tolk value = 0 (no message value economics)"
  expect (tolk.contains s!"dest: (0, 0x{destHex} as uint256)")
    "tolk dest = (0, SHA-256 stub as uint256)"
  expect (tolk.contains "SEND_MODE_PAY_FEES_SEPARATELY") "tolk send mode"
  expect (tolk.contains s!"storeUint({methodOp}, 32)") "tolk body op32 from method hash"
  expect (tolk.contains "storeUint(0, 64)") "tolk query_id = 0"
  expect (tolk.contains "storeUint(") "tolk arg storeUint present"
  -- External log path (emit) must not be confused with schedule path
  expect (!tolk.contains "createExternalLogMessage") "schedule does not emit external log"
  -- StateCell shapes remain intact: no schedule on StateCell
  let stateCell ← compileSource session stateCellSourceText stateCellModuleName
    "<ton-stateCell-sched-reg>"
  let cPlan ← liftResult <| planTon stateCell
  expect (!planUsesPromiseV1 cPlan) "StateCell plan has no schedule"
  let cFiles ← liftResult <| filesTon stateCell
  let cTolk ← findFile cFiles "StateCell.tolk"
  expect (!cTolk.contains "createMessage({") "StateCell.tolk has no createMessage"
  expect (cTolk.contains "struct Storage") "StateCell Storage preserved"
  expect (cTolk.contains "fun onInternalMessage") "StateCell entry preserved"
  IO.println "  ✓ schedule Plan/IR/Tolk createMessage pins"

/-- BL-14: UInt8 state/param/body + narrowCheckedAdd guard sequence. -/
private unsafe def testNarrowUInt8
    (session : Language.Loader.ParserSession) : IO Unit := do
  let src := wrapProgram "NarrowU8" <|
    "  state s : UInt8\n\n" ++
    "  init(x : UInt8) do\n" ++
    "    s := x\n\n" ++
    "  entry go(d : UInt8) : UInt8 do\n" ++
    "    s := s + d\n" ++
    "    return s\n\n" ++
    "  view peek() : UInt8 do\n" ++
    "    return s\n"
  let compiled ← compileSource session src "Examples.NarrowU8" "<ton-u8>"
  let plan ← liftResult <| planTon compiled
  expect (plan.storage.fields.size == 1) "UInt8 one state field"
  expect (plan.storage.fields[0]!.byteWidth == 1) "UInt8 state byteWidth=1"
  expect (plan.storage.fields[0]!.name == "s") "UInt8 state name"
  let some go := plan.entries.find? (·.name == "go") |
    throw <| IO.userError "missing go"
  expect (go.resultKind == .uint8) "go returns UInt8"
  expect (go.params.size == 1 && go.params[0]!.byteWidth == 1) "go param byteWidth=1"
  -- Body must lower narrow checked add (not historical UInt64 checkedAdd).
  let hasNarrowAdd := go.body.any fun s =>
    match s with
    | .store store =>
        match store.value with
        | .narrowCheckedAdd 8 _ _ => true
        | _ => false
    | _ => false
  expect hasNarrowAdd "entry go uses narrowCheckedAdd 8"
  match validatePlan plan with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"NarrowU8 plan validate: {e.render}"
  let ir ← liftResult <| irTon compiled
  let some goIR := ir.methods.find? (·.name == "go") |
    throw <| IO.userError "missing IR go"
  let hasNarrowOp := goIR.operations.any fun
    | .narrowCheckedAdd 8 _ _ _ => true
    | _ => false
  expect hasNarrowOp "IR emits narrowCheckedAdd 8"
  let files ← liftResult <| filesTon compiled
  let tolk ← findFile files "NarrowU8.tolk"
  expect (tolk.contains "s: uint8") "Storage field s: uint8"
  expect (tolk.contains "body.loadUint(8)") "param loadUint(8)"
  expect (tolk.contains s!"(1 << 8)") "UInt8 range guard bound"
  expect (tolk.contains s!"throw {errOverflow}") "overflow code 100"
  expect (tolk.contains "get fun peek()") "view peek present"
  let abi ← findFile files "NarrowU8.ton-abi.json"
  expect (abi.contains "\"type\":\"uint8\"") "ABI uint8 type"
  expect (abi.contains "\"returns\":\"uint8\"") "ABI returns uint8"
  IO.println "  ✓ UInt8 state/param/body + narrow guard"

/-- BL-14: UInt16 + UInt32 mixed state/param pin exact widths and guards. -/
private unsafe def testNarrowUInt16UInt32
    (session : Language.Loader.ParserSession) : IO Unit := do
  let src := wrapProgram "NarrowMix" <|
    "  state a : UInt16\n" ++
    "  state b : UInt32\n\n" ++
    "  init(x : UInt16, y : UInt32) do\n" ++
    "    a := x\n" ++
    "    b := y\n\n" ++
    "  entry bump(d : UInt16) : UInt16 do\n" ++
    "    a := a + d\n" ++
    "    return a\n\n" ++
    "  entry grow(d : UInt32) : UInt32 do\n" ++
    "    b := b + d\n" ++
    "    return b\n\n" ++
    "  view getA() : UInt16 do\n" ++
    "    return a\n\n" ++
    "  view getB() : UInt32 do\n" ++
    "    return b\n"
  let compiled ← compileSource session src "Examples.NarrowMix" "<ton-mix>"
  let plan ← liftResult <| planTon compiled
  expect (plan.storage.fields.size == 2) "two narrow fields"
  expect (plan.storage.fields[0]!.byteWidth == 2) "UInt16 byteWidth=2"
  expect (plan.storage.fields[1]!.byteWidth == 4) "UInt32 byteWidth=4"
  let some bump := plan.entries.find? (·.name == "bump") |
    throw <| IO.userError "missing bump"
  let some grow := plan.entries.find? (·.name == "grow") |
    throw <| IO.userError "missing grow"
  expect (bump.resultKind == .uint16 && grow.resultKind == .uint32)
    "bump/grow result kinds"
  let files ← liftResult <| filesTon compiled
  let tolk ← findFile files "NarrowMix.tolk"
  expect (tolk.contains "a: uint16") "Storage a: uint16"
  expect (tolk.contains "b: uint32") "Storage b: uint32"
  expect (tolk.contains "body.loadUint(16)") "param loadUint(16)"
  expect (tolk.contains "body.loadUint(32)") "param loadUint(32)"
  expect (tolk.contains s!"(1 << 16)") "UInt16 range guard"
  expect (tolk.contains s!"(1 << 32)") "UInt32 range guard"
  -- Historical UInt64 StateCell surface still uses (1 << 64); mix must not drop it
  -- when absent — pin only that narrow bounds are present.
  let abi ← findFile files "NarrowMix.ton-abi.json"
  expect (abi.contains "\"type\":\"uint16\"") "ABI uint16"
  expect (abi.contains "\"type\":\"uint32\"") "ABI uint32"
  IO.println "  ✓ UInt16/UInt32 state/param/body + exact cell widths"

/-- BL-14: Int8 state/param/body + signed narrow guard (loadInt + int8 cell). -/
private unsafe def testNarrowInt8
    (session : Language.Loader.ParserSession) : IO Unit := do
  let src := wrapProgram "NarrowI8" <|
    "  state s : Int8\n\n" ++
    "  init(x : Int8) do\n" ++
    "    s := x\n\n" ++
    "  entry go(d : Int8) : Int8 do\n" ++
    "    s := s + d\n" ++
    "    return s\n\n" ++
    "  view peek() : Int8 do\n" ++
    "    return s\n"
  let compiled ← compileSource session src "Examples.NarrowI8" "<ton-i8>"
  let plan ← liftResult <| planTon compiled
  expect (plan.storage.fields.size == 1) "Int8 one state field"
  expect (plan.storage.fields[0]!.byteWidth == 1) "Int8 state byteWidth=1"
  expect (plan.storage.fields[0]!.isInt) "Int8 state is signed"
  expect (plan.storage.fields[0]!.name == "s") "Int8 state name"
  let some go := plan.entries.find? (·.name == "go") |
    throw <| IO.userError "missing go"
  expect (go.resultKind == .int8) "go returns Int8"
  expect (go.params.size == 1 && go.params[0]!.byteWidth == 1) "go param byteWidth=1"
  expect (go.params[0]!.isInt) "go param is signed"
  let hasNarrowAdd := go.body.any fun s =>
    match s with
    | .store store =>
        match store.value with
        | .narrowSignedCheckedAdd 8 _ _ => true
        | _ => false
    | _ => false
  expect hasNarrowAdd "entry go uses narrowSignedCheckedAdd 8"
  match validatePlan plan with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"NarrowI8 plan validate: {e.render}"
  let ir ← liftResult <| irTon compiled
  let some goIR := ir.methods.find? (·.name == "go") |
    throw <| IO.userError "missing IR go"
  let hasNarrowOp := goIR.operations.any fun
    | .narrowSignedCheckedAdd 8 _ _ _ => true
    | _ => false
  expect hasNarrowOp "IR emits narrowSignedCheckedAdd 8"
  let files ← liftResult <| filesTon compiled
  let tolk ← findFile files "NarrowI8.tolk"
  expect (tolk.contains "s: int8") "Storage field s: int8"
  expect (tolk.contains "body.loadInt(8)") "param loadInt(8)"
  expect (tolk.contains "-(1 << 7)") "Int8 range min bound"
  expect (tolk.contains "(1 << 7)") "Int8 range max bound"
  expect (tolk.contains s!"throw {errOverflow}") "overflow code 100"
  expect (tolk.contains "get fun peek()") "view peek present"
  let abi ← findFile files "NarrowI8.ton-abi.json"
  expect (abi.contains "\"type\":\"int8\"") "ABI int8 type"
  expect (abi.contains "\"returns\":\"int8\"") "ABI returns int8"
  IO.println "  ✓ Int8 state/param/body + signed narrow guard"

/-- BL-14: Int16 + Int32 mixed state/param pin exact signed cell widths. -/
private unsafe def testNarrowInt16Int32
    (session : Language.Loader.ParserSession) : IO Unit := do
  let src := wrapProgram "NarrowIMix" <|
    "  state a : Int16\n" ++
    "  state b : Int32\n\n" ++
    "  init(x : Int16, y : Int32) do\n" ++
    "    a := x\n" ++
    "    b := y\n\n" ++
    "  entry bump(d : Int16) : Int16 do\n" ++
    "    a := a + d\n" ++
    "    return a\n\n" ++
    "  entry grow(d : Int32) : Int32 do\n" ++
    "    b := b + d\n" ++
    "    return b\n\n" ++
    "  view getA() : Int16 do\n" ++
    "    return a\n\n" ++
    "  view getB() : Int32 do\n" ++
    "    return b\n"
  let compiled ← compileSource session src "Examples.NarrowIMix" "<ton-imix>"
  let plan ← liftResult <| planTon compiled
  expect (plan.storage.fields.size == 2) "two signed narrow fields"
  expect (plan.storage.fields[0]!.byteWidth == 2 && plan.storage.fields[0]!.isInt)
    "Int16 byteWidth=2 signed"
  expect (plan.storage.fields[1]!.byteWidth == 4 && plan.storage.fields[1]!.isInt)
    "Int32 byteWidth=4 signed"
  let some bump := plan.entries.find? (·.name == "bump") |
    throw <| IO.userError "missing bump"
  let some grow := plan.entries.find? (·.name == "grow") |
    throw <| IO.userError "missing grow"
  expect (bump.resultKind == .int16 && grow.resultKind == .int32)
    "bump/grow signed result kinds"
  let files ← liftResult <| filesTon compiled
  let tolk ← findFile files "NarrowIMix.tolk"
  expect (tolk.contains "a: int16") "Storage a: int16"
  expect (tolk.contains "b: int32") "Storage b: int32"
  expect (tolk.contains "body.loadInt(16)") "param loadInt(16)"
  expect (tolk.contains "body.loadInt(32)") "param loadInt(32)"
  expect (tolk.contains "-(1 << 15)") "Int16 range min"
  expect (tolk.contains "-(1 << 31)") "Int32 range min"
  let abi ← findFile files "NarrowIMix.ton-abi.json"
  expect (abi.contains "\"type\":\"int16\"") "ABI int16"
  expect (abi.contains "\"type\":\"int32\"") "ABI int32"
  IO.println "  ✓ Int16/Int32 state/param/body + exact signed cell widths"

/-- Array/Map/Option of Int stay fail closed (scalar Int only). -/
private unsafe def testSignedContainerFc
    (session : Language.Loader.ParserSession) : IO Unit := do
  let srcArr := wrapProgram "ArrI8" <|
    "  state slots : Array Int8 2\n\n" ++
    "  init() do\n" ++
    "    slots[0] := 0\n" ++
    "    slots[1] := 0\n\n" ++
    "  entry set0(v : UInt64) : UInt64 do\n" ++
    "    slots[0] := 0\n" ++
    "    return v\n"
  let compiledArr ← compileSource session srcArr "Examples.ArrI8" "<ton-arr-i8>"
  match planTon compiledArr with
  | .error (.planInvariant .ton msg) =>
      expect (msg.contains "Array state element must be UInt64")
        s!"ArrI8 FC must cite Array UInt64 element, got: {msg}"
  | .error e => throw <| IO.userError s!"ArrI8: unexpected {e.render}"
  | .ok _ => throw <| IO.userError "ArrI8: expected FC, got ok"
  let srcMap := wrapProgram "MapI32" <|
    "  state m : Map Int32 UInt64\n\n" ++
    "  init() do\n" ++
    "    m := Map.empty()\n\n" ++
    "  entry put(k : UInt64, v : UInt64) : UInt64 do\n" ++
    "    return v\n"
  let compiledMap ← compileSource session srcMap "Examples.MapI32" "<ton-map-i32>"
  match planTon compiledMap with
  | .error (.planInvariant .ton msg) =>
      expect (msg.contains "Map state admits only Map UInt64 UInt64")
        s!"MapI32 FC must cite Map UInt64 UInt64, got: {msg}"
  | .error e => throw <| IO.userError s!"MapI32: unexpected {e.render}"
  | .ok _ => throw <| IO.userError "MapI32: expected FC, got ok"
  let srcOpt := wrapProgram "OptI8" <|
    "  state o : Option Int8\n\n" ++
    "  init() do\n" ++
    "    o := Option.none()\n\n" ++
    "  view get() : UInt64 do\n" ++
    "    return 0\n"
  let compiledOpt ← compileSource session srcOpt "Examples.OptI8" "<ton-opt-i8>"
  match planTon compiledOpt with
  | .error (.planInvariant .ton msg) =>
      expect (msg.contains "Option state 'o' requires UInt64 payload")
        s!"OptI8 FC must cite Option UInt64 payload, got: {msg}"
  | .error e => throw <| IO.userError s!"OptI8: unexpected {e.render}"
  | .ok _ => throw <| IO.userError "OptI8: expected FC, got ok"
  IO.println "  ✓ Array/Map/Option of Int stay fail closed"

/-- BL-14: UInt128/256 and Int128 stay fail closed. -/
private unsafe def testMultiWidthFc
    (session : Language.Loader.ParserSession) : IO Unit := do
  -- UInt128 state/param/return
  let src128 := wrapProgram "Wide128" <|
    "  state s : UInt128\n\n" ++
    "  init(x : UInt128) do\n" ++
    "    s := x\n\n" ++
    "  entry go(d : UInt128) : UInt128 do\n" ++
    "    s := s + d\n" ++
    "    return s\n\n" ++
    "  view peek() : UInt128 do\n" ++
    "    return s\n"
  match ← (do
      try
        let c ← compileSource session src128 "Examples.Wide128" "<ton-u128-fc>"
        pure (some c)
      catch _ => pure none) with
  | none => pure ()  -- may fail at Normalize if not admitted
  | some c =>
      match planTon c with
      | .error (.planInvariant .ton msg) =>
          expect (msg.length > 0) "UInt128 planInvariant nonempty"
          expect (
              msg.contains "128" || msg.contains "multi-width" ||
              msg.contains "UInt" || msg.contains "admitted" ||
              msg.contains "integer" || msg.contains "fail closed")
            s!"UInt128 FC message must cite width/admitted, got: {msg}"
      | .error e => throw <| IO.userError s!"UInt128: unexpected {e.render}"
      | .ok _ => throw <| IO.userError "UInt128: expected FC, got ok"
  -- UInt256
  let src256 := wrapProgram "Wide256" <|
    "  state s : UInt256\n\n" ++
    "  init(x : UInt256) do\n" ++
    "    s := x\n\n" ++
    "  entry go(d : UInt256) : UInt256 do\n" ++
    "    s := s + d\n" ++
    "    return s\n\n" ++
    "  view peek() : UInt256 do\n" ++
    "    return s\n"
  match ← (do
      try
        let c ← compileSource session src256 "Examples.Wide256" "<ton-u256-fc>"
        pure (some c)
      catch _ => pure none) with
  | none => pure ()
  | some c =>
      match planTon c with
      | .error (.planInvariant .ton msg) =>
          expect (msg.length > 0) "UInt256 planInvariant nonempty"
      | .error e => throw <| IO.userError s!"UInt256: unexpected {e.render}"
      | .ok _ => throw <| IO.userError "UInt256: expected FC, got ok"
  -- Int128 stays fail closed (narrow Int8/16/32 admitted separately).
  let srcI128 := wrapProgram "WideI128" <|
    "  state s : Int128\n\n" ++
    "  init(x : Int128) do\n" ++
    "    s := x\n\n" ++
    "  entry go(d : Int128) : Int128 do\n" ++
    "    s := s + d\n" ++
    "    return s\n\n" ++
    "  view peek() : Int128 do\n" ++
    "    return s\n"
  match ← (do
      try
        let c ← compileSource session srcI128 "Examples.WideI128" "<ton-i128-fc>"
        pure (some c)
      catch _ => pure none) with
  | none => pure ()
  | some c =>
      match planTon c with
      | .error (.planInvariant .ton msg) =>
          expect (msg.contains "Int128" || msg.contains "128" ||
              msg.contains "fail closed" || msg.contains "integer")
            s!"Int128 FC message must cite width, got: {msg}"
      | .error e => throw <| IO.userError s!"Int128: unexpected {e.render}"
      | .ok _ => throw <| IO.userError "Int128: expected FC, got ok"
  IO.println "  ✓ UInt128/256 + Int128 fail closed"

private unsafe def testRegistryDispatch
    (session : Language.Loader.ParserSession) : IO Unit := do
  let compiled ← compileSource session stateCellSourceText stateCellModuleName
    "<ton-registry>"
  let capability ← liftResult <| tonCapability compiled
  let artifacts ← liftResult <| Targets.materializeResult capability
  expect (MaterializedArtifactsV1.artifactProgramNameOf artifacts == "StateCell")
    "registry materialize program name"
  let files := MaterializedArtifactsV1.filesOf artifacts
  expect (files.any (·.path == "StateCell.tolk")) "registry emits .tolk"
  expect (files.any (·.path == "StateCell.ton-abi.json")) "registry emits ton-abi"
  IO.println "  ✓ Registry materialize dispatch"

private def findMethod (plan : Plan) (name : String) : IO Method :=
  match plan.entries.find? (·.name == name) with
  | some m => pure m
  | none => throw <| IO.userError s!"missing method '{name}'"

private def findMethodIR (ir : IR) (name : String) : IO MethodIR :=
  match ir.methods.find? (·.name == name) with
  | some m => pure m
  | none => throw <| IO.userError s!"missing IR method '{name}'"

/-- B-RET-ABI: named Struct view return flattens to 2×UInt64 leaves via
`returnAggregate` / `setReturnDataLeaves` / Tolk tuple get-method. -/
private unsafe def testNamedStructReturn
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrapProgram "PairRet" <|
    "  struct Pair where\n" ++
    "    a : UInt64\n" ++
    "    b : UInt64\n" ++
    "  state p : Pair\n\n" ++
    "  init(x : UInt64, y : UInt64) do\n" ++
    "    p := Pair.new(x, y)\n\n" ++
    "  view getPair() : Pair do\n" ++
    "    return p\n"
  let compiled ← compileSource session source "Examples.PairRet" "<ton-pair-ret>"
  let plan ← liftResult (planTon compiled)
  let getPair ← findMethod plan "getPair"
  expect (getPair.mode == .view) "PairRet getPair must be view"
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
      -- Preorder: p_a then p_b → two stateLoad of the two fields.
      match leaves[0]!, leaves[1]! with
      | .stateLoad fi0, .stateLoad fi1 =>
          expect (fi0 + 1 == fi1)
            s!"PairRet leaf order must be consecutive field indices, got {fi0}/{fi1}"
      | _, _ =>
          throw <| IO.userError
            "PairRet returnAggregate leaves must be stateLoad of p fields"
  | _ =>
      throw <| IO.userError "PairRet getPair body must be .returnAggregate"
  match validatePlan plan with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"PairRet plan must validate: {e.render}"
  let d ← match engineeringTonPlanDigestV1 plan with
    | .ok d => pure d
    | .error e => throw <| IO.userError e
  let d2 ← match engineeringTonPlanDigestV1 plan with
    | .ok d => pure d
    | .error e => throw <| IO.userError e
  expect (d == d2) "PairRet plan digest deterministic"
  let ir ← liftResult (irTon compiled)
  let getPairIR ← findMethodIR ir "getPair"
  expect (getPairIR.resultKind == getPair.resultKind)
    "PairRet IR resultKind must match Plan"
  let mut sawLeaves := false
  for op in getPairIR.operations do
    match op with
    | .setReturnDataLeaves temps =>
        expect (temps.size == 2)
          s!"setReturnDataLeaves must have 2 temps, got {temps.size}"
        sawLeaves := true
    | .setReturnData _ =>
        throw <| IO.userError "PairRet must not emit scalar setReturnData"
    | _ => pure ()
  expect sawLeaves "PairRet IR must emit setReturnDataLeaves"
  let files ← liftResult (filesTon compiled)
  let tolk ← findFile files "PairRet.tolk"
  expect (tolk.contains "get fun getPair(): (int, int)")
    s!"PairRet Tolk must declare tuple return type, got snippet around getPair"
  expect (tolk.contains "return (")
    "PairRet Tolk must emit multi-value return ("
  expect (tolk.contains "struct Storage") "PairRet Storage preserved"
  let abi ← findFile files "PairRet.ton-abi.json"
  expect (abi.contains "\"returns\":[\"uint64\",\"uint64\"]")
    s!"PairRet ABI must declare leaf tuple [\"uint64\",\"uint64\"], got: {abi}"
  IO.println "  ✓ PairRet named Struct view return Plan/IR/Tolk/ABI pin"

/-- B-RET-ABI: named Enum view return = tag + max-payload slots (Maybe = 2). -/
private unsafe def testNamedEnumReturn
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrapProgram "MaybeRet" <|
    "  enum Maybe where\n" ++
    "    | None\n" ++
    "    | Some(UInt64)\n" ++
    "  state m : Maybe\n\n" ++
    "  init() do\n" ++
    "    m := Maybe.None()\n\n" ++
    "  entry put(v : UInt64) : UInt64 do\n" ++
    "    m := Maybe.Some(v)\n" ++
    "    return v\n\n" ++
    "  view peek() : Maybe do\n" ++
    "    return m\n"
  let compiled ← compileSource session source "Examples.MaybeRet" "<ton-maybe-ret>"
  let plan ← liftResult (planTon compiled)
  let peek ← findMethod plan "peek"
  match peek.resultKind with
  | .aggregate leaves =>
      expect (leaves.size == 2)
        s!"MaybeRet Enum return must be tag+payload (2), got {leaves.size}"
  | other =>
      throw <| IO.userError
        s!"MaybeRet peek resultKind must be .aggregate, got {repr other}"
  match peek.body[0]! with
  | .returnAggregate leaves leafIsInt =>
      expect (leaves.size == 2 && leafIsInt.size == 2)
        "MaybeRet returnAggregate must have 2 leaves"
  | _ =>
      throw <| IO.userError "MaybeRet peek body must be .returnAggregate"
  match validatePlan plan with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"MaybeRet plan must validate: {e.render}"
  let ir ← liftResult (irTon compiled)
  let peekIR ← findMethodIR ir "peek"
  expect (peekIR.operations.any fun
      | .setReturnDataLeaves t => t.size == 2
      | _ => false)
    "MaybeRet peek IR must emit setReturnDataLeaves [2]"
  let files ← liftResult (filesTon compiled)
  let tolk ← findFile files "MaybeRet.tolk"
  expect (tolk.contains "get fun peek(): (int, int)")
    "MaybeRet Tolk must declare 2-leaf tuple return"
  let abi ← findFile files "MaybeRet.ton-abi.json"
  expect (abi.contains "\"returns\":[\"uint64\",\"uint64\"]")
    s!"MaybeRet ABI must declare [\"uint64\",\"uint64\"], got: {abi}"
  IO.println "  ✓ MaybeRet named Enum view return Plan/IR/Tolk pin"

/-- BL-23 / N-ANON-RESULT (TON ABI): anonymous Array UInt64 2 **view** return
flattens to 2×UInt64 leaves via `returnAggregate` / `setReturnDataLeaves` /
Tolk multi-stack get-method (same path as named Struct). Entry aggregate
stays fail closed (TON async actor has no return channel). -/
private unsafe def testAnonymousArrayReturn
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrapProgram "ArrayRet" <|
    "  state slots : Array UInt64 2\n\n" ++
    "  init(x : UInt64, y : UInt64) do\n" ++
    "    slots[0] := x\n" ++
    "    slots[1] := y\n\n" ++
    "  entry setArr(x : UInt64, y : UInt64) : UInt64 do\n" ++
    "    slots[0] := x\n" ++
    "    slots[1] := y\n" ++
    "    return x\n\n" ++
    "  view getArr() : Array UInt64 2 do\n" ++
    "    return slots\n"
  let compiled ← compileSource session source "Examples.ArrayRet" "<ton-array-ret>"
  let plan ← liftResult (planTon compiled)
  expect (plan.storage.fields.size == 2)
    "ArrayRet: Array UInt64 2 → 2 c4 leaves"
  let getArr ← findMethod plan "getArr"
  expect (getArr.mode == .view) "ArrayRet getArr must be view"
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
      | .stateLoad fi0, .stateLoad fi1 =>
          expect (fi0 + 1 == fi1)
            s!"ArrayRet leaf order must be consecutive field indices, got {fi0}/{fi1}"
      | _, _ =>
          throw <| IO.userError
            "ArrayRet returnAggregate leaves must be stateLoad of slots fields"
  | _ =>
      throw <| IO.userError "ArrayRet getArr body must be .returnAggregate"
  match validatePlan plan with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"ArrayRet plan must validate: {e.render}"
  let d ← match engineeringTonPlanDigestV1 plan with
    | .ok d => pure d
    | .error e => throw <| IO.userError e
  let d2 ← match engineeringTonPlanDigestV1 plan with
    | .ok d => pure d
    | .error e => throw <| IO.userError e
  expect (d == d2) "ArrayRet plan digest deterministic"
  let ir ← liftResult (irTon compiled)
  let getArrIR ← findMethodIR ir "getArr"
  expect (getArrIR.resultKind == getArr.resultKind)
    "ArrayRet IR resultKind must match Plan"
  let mut sawLeaves := false
  for op in getArrIR.operations do
    match op with
    | .setReturnDataLeaves temps =>
        expect (temps.size == 2)
          s!"setReturnDataLeaves must have 2 temps, got {temps.size}"
        sawLeaves := true
    | .setReturnData _ =>
        throw <| IO.userError "ArrayRet must not emit scalar setReturnData"
    | _ => pure ()
  expect sawLeaves "ArrayRet IR must emit setReturnDataLeaves"
  let files ← liftResult (filesTon compiled)
  let tolk ← findFile files "ArrayRet.tolk"
  expect (tolk.contains "get fun getArr(): (int, int)")
    s!"ArrayRet Tolk must declare tuple return type, got snippet around getArr"
  expect (tolk.contains "return (")
    "ArrayRet Tolk must emit multi-value return ("
  expect (tolk.contains "struct Storage") "ArrayRet Storage preserved"
  let abi ← findFile files "ArrayRet.ton-abi.json"
  expect (abi.contains "\"returns\":[\"uint64\",\"uint64\"]")
    s!"ArrayRet ABI must declare leaf tuple [\"uint64\",\"uint64\"], got: {abi}"
  IO.println "  ✓ ArrayRet anonymous Array view return Plan/IR/Tolk/ABI pin"

/-- BL-23 / N-ANON-RESULT: anonymous Option UInt64 view return = tag + payload
(none=(0,0), some v=(1,v)); entry Option return stays fail closed. -/
private unsafe def testAnonymousOptionReturn
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrapProgram "OptionRet" <|
    "  state seed : UInt64\n\n" ++
    "  init(s : UInt64) do\n" ++
    "    seed := s\n\n" ++
    "  entry put(v : UInt64) : UInt64 do\n" ++
    "    seed := v\n" ++
    "    return v\n\n" ++
    "  view asNone() : Option UInt64 do\n" ++
    "    return Option.none()\n\n" ++
    "  view asSomeOfSeed() : Option UInt64 do\n" ++
    "    return Option.some(seed)\n"
  let compiled ← compileSource session source "Examples.OptionRet"
    "<ton-option-ret>"
  let plan ← liftResult (planTon compiled)
  let asNone ← findMethod plan "asNone"
  expect (asNone.mode == .view) "OptionRet asNone must be view"
  match asNone.resultKind with
  | .aggregate leaves =>
      expect (leaves.size == 2)
        s!"OptionRet none return must be tag+payload (2), got {leaves.size}"
      expect (leaves.all (fun l => !l.isInt && l.byteWidth == 8))
        "OptionRet leaves must be u64 words"
  | other =>
      throw <| IO.userError
        s!"OptionRet asNone resultKind must be .aggregate, got {repr other}"
  match asNone.body[0]! with
  | .returnAggregate leaves leafIsInt =>
      expect (leaves.size == 2 && leafIsInt == #[false, false])
        "OptionRet asNone returnAggregate must have 2 u64 leaves"
      match leaves[0]!, leaves[1]! with
      | .literal t, .literal p =>
          expect (t == 0 && p == 0)
            s!"Option.none must lower to (0,0), got ({t},{p})"
      | _, _ =>
          throw <| IO.userError
            "OptionRet asNone leaves must be literal tag/payload"
  | _ =>
      throw <| IO.userError "OptionRet asNone body must be .returnAggregate"
  let asSome ← findMethod plan "asSomeOfSeed"
  match asSome.resultKind with
  | .aggregate leaves =>
      expect (leaves.size == 2)
        "OptionRet some return must be tag+payload (2)"
  | other =>
      throw <| IO.userError
        s!"OptionRet asSomeOfSeed resultKind must be .aggregate, got {repr other}"
  match asSome.body[0]! with
  | .returnAggregate leaves leafIsInt =>
      expect (leaves.size == 2 && leafIsInt == #[false, false])
        "OptionRet asSomeOfSeed returnAggregate must have 2 u64 leaves"
      match leaves[0]!, leaves[1]! with
      | .literal t, .stateLoad _ =>
          expect (t == 1) s!"Option.some tag must be 1, got {t}"
      | _, _ =>
          throw <| IO.userError
            "OptionRet asSomeOfSeed leaves must be literal 1 + stateLoad seed"
  | _ =>
      throw <| IO.userError "OptionRet asSomeOfSeed body must be .returnAggregate"
  match validatePlan plan with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"OptionRet plan must validate: {e.render}"
  let ir ← liftResult (irTon compiled)
  let noneIR ← findMethodIR ir "asNone"
  expect (noneIR.operations.any fun
      | .setReturnDataLeaves t => t.size == 2
      | _ => false)
    "OptionRet asNone IR must emit setReturnDataLeaves [2]"
  let someIR ← findMethodIR ir "asSomeOfSeed"
  expect (someIR.operations.any fun
      | .setReturnDataLeaves t => t.size == 2
      | _ => false)
    "OptionRet asSomeOfSeed IR must emit setReturnDataLeaves [2]"
  let files ← liftResult (filesTon compiled)
  let tolk ← findFile files "OptionRet.tolk"
  expect (tolk.contains "get fun asNone(): (int, int)")
    "OptionRet Tolk must declare 2-leaf tuple return for asNone"
  expect (tolk.contains "get fun asSomeOfSeed(): (int, int)")
    "OptionRet Tolk must declare 2-leaf tuple return for asSomeOfSeed"
  expect (tolk.contains "return (")
    "OptionRet Tolk must emit multi-value return ("
  let abi ← findFile files "OptionRet.ton-abi.json"
  expect (abi.contains "\"returns\":[\"uint64\",\"uint64\"]")
    s!"OptionRet ABI must declare [\"uint64\",\"uint64\"], got: {abi}"
  IO.println "  ✓ OptionRet anonymous Option view return Plan/IR/Tolk/ABI pin"

/-- Fail-closed: entry aggregate (named + anonymous), Map/Bytes returns, >8
leaves (named + Array), nested Option, non-UInt64 Array element. -/
private unsafe def testAggregateFailClosed
    (session : Language.Loader.ParserSession) : IO Unit := do
  -- Entry (mutate) named Struct return stays fail-closed (TON async actor).
  let entrySrc := wrapProgram "StructEntryRet" <|
    "  struct Pair where\n" ++
    "    a : UInt64\n" ++
    "    b : UInt64\n" ++
    "  state p : Pair\n\n" ++
    "  init() do\n" ++
    "    p := Pair.new(0, 0)\n\n" ++
    "  entry getPair() : Pair do\n" ++
    "    return p\n"
  let entryCompiled ← compileSource session entrySrc "Examples.StructEntryRet"
    "<ton-struct-entry-ret>"
  expectPlanErrorContaining "StructEntryRet" "view-only"
    (planTon entryCompiled)
  match planTon entryCompiled with
  | .error (.planInvariant .ton msg) =>
      expect (msg.contains "multi-leaf" || msg.contains "return channel" ||
          msg.contains "named")
        s!"StructEntryRet message must cite multi-leaf / return channel, got: {msg}"
  | .error e => throw <| IO.userError s!"StructEntryRet: unexpected {e.render}"
  | .ok _ => throw <| IO.userError "StructEntryRet: expected FC, got ok"
  -- Entry (mutate) anonymous Array return stays fail-closed (same honesty).
  let arrEntrySrc := wrapProgram "ArrayEntryRet" <|
    "  state slots : Array UInt64 2\n\n" ++
    "  init() do\n" ++
    "    slots[0] := 0\n" ++
    "    slots[1] := 0\n\n" ++
    "  entry getArr() : Array UInt64 2 do\n" ++
    "    return slots\n"
  let arrEntryCompiled ← compileSource session arrEntrySrc "Examples.ArrayEntryRet"
    "<ton-array-entry-ret>"
  expectPlanErrorContaining "ArrayEntryRet" "view-only"
    (planTon arrEntryCompiled)
  -- Entry Option return stays fail-closed.
  let optEntrySrc := wrapProgram "OptionEntryRet" <|
    "  state seed : UInt64\n\n" ++
    "  init() do\n" ++
    "    seed := 0\n\n" ++
    "  entry getOpt() : Option UInt64 do\n" ++
    "    return Option.some(seed)\n"
  let optEntryCompiled ← compileSource session optEntrySrc "Examples.OptionEntryRet"
    "<ton-option-entry-ret>"
  expectPlanErrorContaining "OptionEntryRet" "view-only"
    (planTon optEntryCompiled)
  -- Cap-8: Struct with 9 UInt64 fields exceeds B-RET-ABI leaf cap.
  let mut fields := ""
  for i in [0:9] do
    fields := fields ++ s!"    f{i} : UInt64\n"
  let wideSource := wrapProgram "WideRet" <|
    "  struct Wide where\n" ++
    fields ++
    "  state w : Wide\n\n" ++
    "  init() do\n" ++
    "    w := Wide.new(0, 0, 0, 0, 0, 0, 0, 0, 0)\n\n" ++
    "  view getWide() : Wide do\n" ++
    "    return w\n"
  match ← (do
      try
        let c ← compileSource session wideSource "Examples.WideRet" "<ton-wide-ret>"
        pure (some c)
      catch _ => pure none) with
  | none => pure ()
  | some c =>
      match planTon c with
      | .error e =>
          expect (e.render.contains "8" || e.render.contains "leaf" ||
              e.render.contains "aggregate")
            s!"WideRet leaf-cap error must cite cap/leaf/aggregate, got: {e.render}"
      | .ok _ =>
          throw <| IO.userError
            "Ton 9-leaf aggregate return must fail closed (cap-8)"
  -- Array UInt64 9 exceeds leaf cap-8.
  let arrWideSrc := wrapProgram "ArrayWideRet" <|
    "  state slots : Array UInt64 9\n\n" ++
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
    "    return slots\n"
  match ← (do
      try
        let c ← compileSource session arrWideSrc "Examples.ArrayWideRet"
          "<ton-array-wide-ret>"
        pure (some c)
      catch _ => pure none) with
  | none => pure ()
  | some c =>
      match planTon c with
      | .error e =>
          expect (e.render.contains "8" || e.render.contains "leaf" ||
              e.render.contains "aggregate")
            s!"ArrayWideRet leaf-cap error must cite cap/leaf/aggregate, got: {e.render}"
      | .ok _ =>
          throw <| IO.userError
            "Ton Array UInt64 9 view return must fail closed (cap-8)"
  -- Map return stays fail closed with precise message.
  let mapSrc := wrapProgram "MapRet" <|
    "  state m : Map UInt64 UInt64\n\n" ++
    "  init() do\n" ++
    "    m[0] := 0\n\n" ++
    "  view getMap() : Map UInt64 UInt64 do\n" ++
    "    return m\n"
  match ← (do
      try
        let c ← compileSource session mapSrc "Examples.MapRet" "<ton-map-ret>"
        pure (some c)
      catch _ => pure none) with
  | none => pure ()
  | some c =>
      match planTon c with
      | .error (.planInvariant .ton msg) =>
          expect (msg.contains "Map" || msg.contains "B-RET" ||
              msg.contains "outside")
            s!"MapRet FC message must cite Map/B-RET, got: {msg}"
      | .error e => throw <| IO.userError s!"MapRet: unexpected {e.render}"
      | .ok _ => throw <| IO.userError "MapRet: expected FC, got ok"
  -- Bytes return stays fail closed with precise message.
  let bytesSrc := wrapProgram "BytesRet" <|
    "  state b : Bytes 4\n\n" ++
    "  init() do\n" ++
    "    b[0] := 0\n\n" ++
    "  view getBytes() : Bytes 4 do\n" ++
    "    return b\n"
  match ← (do
      try
        let c ← compileSource session bytesSrc "Examples.BytesRet" "<ton-bytes-ret>"
        pure (some c)
      catch _ => pure none) with
  | none => pure ()
  | some c =>
      match planTon c with
      | .error (.planInvariant .ton msg) =>
          expect (msg.contains "Bytes" || msg.contains "B-RET" ||
              msg.contains "outside")
            s!"BytesRet FC message must cite Bytes/B-RET, got: {msg}"
      | .error e => throw <| IO.userError s!"BytesRet: unexpected {e.render}"
      | .ok _ => throw <| IO.userError "BytesRet: expected FC, got ok"
  -- Nested anonymous Option (Array …) remains fail closed (non-UInt64 payload).
  let nestedSrc := wrapProgram "NestedOptRet" <|
    "  state pad : UInt64\n\n" ++
    "  init() do\n" ++
    "    pad := 0\n\n" ++
    "  view getNested() : Option Array UInt64 2 do\n" ++
    "    return Option.none()\n"
  match ← (do
      try
        let c ← compileSource session nestedSrc "Examples.NestedOptRet"
          "<ton-nested-opt-ret>"
        pure (some c)
      catch _ => pure none) with
  | none => pure ()  -- may fail earlier at typed/Normalize
  | some c =>
      match planTon c with
      | .error (.planInvariant .ton msg) =>
          expect (msg.contains "Option" || msg.contains "UInt64" ||
              msg.contains "payload" || msg.contains "Array" ||
              msg.contains "anonymous")
            s!"NestedOptRet FC must cite Option/UInt64/payload, got: {msg}"
      | .error e => throw <| IO.userError s!"NestedOptRet: unexpected {e.render}"
      | .ok _ => throw <| IO.userError "NestedOptRet: expected FC, got ok"
  -- Non-UInt64 Array element stays fail closed.
  let narrowArrSrc := wrapProgram "NarrowArrRet" <|
    "  state slots : Array UInt32 2\n\n" ++
    "  init() do\n" ++
    "    slots[0] := 0\n" ++
    "    slots[1] := 0\n\n" ++
    "  view getArr() : Array UInt32 2 do\n" ++
    "    return slots\n"
  match ← (do
      try
        let c ← compileSource session narrowArrSrc "Examples.NarrowArrRet"
          "<ton-narrow-arr-ret>"
        pure (some c)
      catch _ => pure none) with
  | none => pure ()
  | some c =>
      match planTon c with
      | .error (.planInvariant .ton msg) =>
          expect (msg.contains "UInt64" || msg.contains "Array" ||
              msg.contains "element")
            s!"NarrowArrRet FC must cite UInt64/Array element, got: {msg}"
      | .error e => throw <| IO.userError s!"NarrowArrRet: unexpected {e.render}"
      | .ok _ => throw <| IO.userError "NarrowArrRet: expected FC, got ok"
  -- B-OPT-STATE: Option of non-UInt64 state stays fail closed.
  let optBadSource := wrapProgram "OptBadEl" <|
    "  state o : Option UInt8\n\n" ++
    "  init() do\n" ++
    "    o := Option.none()\n\n" ++
    "  view get() : UInt64 do\n" ++
    "    return 0\n"
  match ← (do
      try
        let c ← compileSource session optBadSource "Examples.OptBadEl" "<ton-opt-bad>"
        pure (some c)
      catch _ => pure none) with
  | none => pure ()  -- may fail at Normalize/typed
  | some c =>
      match planTon c with
      | .error e =>
          expect (e.render.contains "Option" || e.render.contains "UInt64" ||
              e.render.contains "payload")
            s!"OptBadEl must cite Option/UInt64/payload, got: {e.render}"
      | .ok _ =>
          throw <| IO.userError
            "Ton Option UInt8 state must fail closed (UInt64 payload only)"
  -- Option param stays fail closed (state/view-return only).
  let optParamSource := wrapProgram "OptParam" <|
    "  state pad : UInt64\n\n" ++
    "  init(i : UInt64) do\n" ++
    "    pad := i\n\n" ++
    "  entry take(o : Option UInt64) : UInt64 do\n" ++
    "    return pad\n"
  match ← (do
      try
        let c ← compileSource session optParamSource "Examples.OptParam" "<ton-opt-param>"
        pure (some c)
      catch _ => pure none) with
  | none => pure ()
  | some c =>
      match planTon c with
      | .error e =>
          expect (e.render.contains "Option" || e.render.contains "parameter" ||
              e.render.contains "param")
            s!"OptParam must cite Option/parameter, got: {e.render}"
      | .ok _ =>
          throw <| IO.userError
            "Ton Option parameter must fail closed (state/view-return only)"
  -- Nested Option state (Option of Option) stays fail closed.
  let nestOptSrc := wrapProgram "NestOptState" <|
    "  state o : Option Option UInt64\n\n" ++
    "  init() do\n" ++
    "    o := Option.none()\n\n" ++
    "  view get() : UInt64 do\n" ++
    "    return 0\n"
  match ← (do
      try
        let c ← compileSource session nestOptSrc "Examples.NestOptState" "<ton-nest-opt>"
        pure (some c)
      catch _ => pure none) with
  | none => pure ()
  | some c =>
      match planTon c with
      | .error e =>
          expect (e.render.contains "Option" || e.render.contains "UInt64" ||
              e.render.contains "payload")
            s!"NestOptState FC must cite Option/UInt64/payload, got: {e.render}"
      | .ok _ =>
          throw <| IO.userError
            "Ton nested Option state must fail closed"
  IO.println "  ✓ aggregate return fail-closed boundaries (entry/Map/Bytes/9-leaf/nested/Option-state)"

/-- BL-34 / B-OPT-STATE: Option UInt64 state = Enum-shaped 2-leaf c4 layout
    (`slot_tag` + `slot_p0`); construct none zeros payload; match read via
    VariantTag/VariantPayload; storeAtomic on assign; locked tolk → .fif. -/
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
    "<ton-option-state>"
  let plan ← liftResult (planTon compiled)
  expect (plan.storage.fields.size == 2)
    s!"OptionState: Option UInt64 must flatten to tag+payload (2), got {plan.storage.fields.size}"
  expect (plan.storage.fields.any fun f => f.name == "slot_tag")
    "OptionState must have slot_tag leaf"
  expect (plan.storage.fields.any fun f => f.name == "slot_p0")
    "OptionState must have slot_p0 payload leaf"
  let some tagF := plan.storage.fields.find? (·.name == "slot_tag") |
    throw <| IO.userError "OptionState missing slot_tag"
  let some payF := plan.storage.fields.find? (·.name == "slot_p0") |
    throw <| IO.userError "OptionState missing slot_p0"
  expect (tagF.byteWidth == 8 && payF.byteWidth == 8)
    "OptionState leaves must be 8-byte UInt64 words"
  expect (tagF.sourceId + 1 == payF.sourceId)
    s!"OptionState leaves must be consecutive sourceIds, got {tagF.sourceId}/{payF.sourceId}"
  -- Init none → storeAtomic both leaves (payload zeroed).
  let mut initAtomic := false
  for stmt in plan.initializer.body do
    match stmt with
    | .storeAtomic leaves =>
        expect (leaves.size == 2)
          s!"Option.none storeAtomic must write 2 leaves, got {leaves.size}"
        expect (leaves[0]!.value == .literal 0 && leaves[1]!.value == .literal 0)
          "Option.none must zero tag and payload (stale-payload pin)"
        expect (leaves[0]!.fieldIndex == tagF.sourceId &&
            leaves[1]!.fieldIndex == payF.sourceId)
          "Option.none must target tag then payload field indices"
        initAtomic := true
    | .store _ =>
        throw <| IO.userError
          "OptionState init must not scalar-store Option leaves"
    | _ => pure ()
  expect initAtomic "OptionState init must emit storeAtomic for Option.none"
  -- set some → storeAtomic (1, param).
  let setH ← findMethod plan "set"
  let mut setAtomic := false
  for stmt in setH.body do
    match stmt with
    | .storeAtomic leaves =>
        expect (leaves.size == 2) "set storeAtomic must write 2 leaves"
        expect (leaves[0]!.value == .literal 1)
          "set Option.some tag must be literal 1"
        match leaves[1]!.value with
        | .param _ => pure ()
        | other =>
            throw <| IO.userError
              s!"set Option.some payload must be param, got {repr other}"
        setAtomic := true
    | _ => pure ()
  expect setAtomic "OptionState set must storeAtomic Option.some"
  -- clear none-reset → storeAtomic zeros both leaves.
  let clearH ← findMethod plan "clear"
  let mut clearAtomic := false
  for stmt in clearH.body do
    match stmt with
    | .storeAtomic leaves =>
        expect (leaves.size == 2) "clear storeAtomic must write 2 leaves"
        expect (leaves[0]!.value == .literal 0 && leaves[1]!.value == .literal 0)
          "clear Option.none must zero tag and payload"
        clearAtomic := true
    | _ => pure ()
  expect clearAtomic "OptionState clear must storeAtomic Option.none"
  -- peek match → body reads both state leaves (VariantTag/VariantPayload path).
  let peekH ← findMethod plan "peek"
  expect (peekH.resultKind == .uint64) "OptionState peek must return UInt64"
  let peekRepr := toString (repr peekH.body)
  expect (peekRepr.contains "stateLoad" || peekRepr.contains "StateLoad")
    s!"peek match must stateLoad Option leaves, body={peekRepr}"
  expect (peekRepr.contains s!"stateLoad {tagF.sourceId}" ||
      peekRepr.contains s!"StateLoad {tagF.sourceId}" ||
      peekRepr.contains (toString tagF.sourceId))
    s!"peek must reference tag field {tagF.sourceId}, body={peekRepr}"
  expect (peekRepr.contains s!"stateLoad {payF.sourceId}" ||
      peekRepr.contains s!"StateLoad {payF.sourceId}" ||
      peekRepr.contains (toString payF.sourceId))
    s!"peek must reference payload field {payF.sourceId}, body={peekRepr}"
  expect (peekRepr.contains "ifThenElse" || peekRepr.contains "switchOn" ||
      peekRepr.contains "IfThenElse" || peekRepr.contains "SwitchOn")
    s!"peek match must lower to ifThenElse/switchOn, body={peekRepr}"
  -- getOpt return of stored Option → 2-leaf aggregate.
  let getOpt ← findMethod plan "getOpt"
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
      | .stateLoad fi0, .stateLoad fi1 =>
          expect (fi0 == tagF.sourceId && fi1 == payF.sourceId)
            s!"OptionState getOpt leaves must be stateLoad tag/payload, got {fi0}/{fi1}"
      | a, b =>
          throw <| IO.userError
            s!"OptionState getOpt leaves must be stateLoads, got {repr a}/{repr b}"
  | _ =>
      throw <| IO.userError "OptionState getOpt must end with .returnAggregate"
  match validatePlan plan with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"OptionState plan must validate: {e.render}"
  let ir ← liftResult (irTon compiled)
  let setIR ← findMethodIR ir "set"
  let mut multiStores := 0
  for op in setIR.operations do
    match op with
    | .storeState _ _ => multiStores := multiStores + 1
    | _ => pure ()
  expect (multiStores >= 2)
    s!"OptionState set IR must storeState both leaves, got {multiStores}"
  let getOptIR ← findMethodIR ir "getOpt"
  expect (getOptIR.operations.any fun
      | .setReturnDataLeaves t => t.size == 2
      | _ => false)
    "OptionState getOpt IR must emit setReturnDataLeaves [2]"
  let files ← liftResult (filesTon compiled)
  let tolk ← findFile files "OptionState.tolk"
  expect (tolk.contains "struct Storage") "OptionState Storage struct"
  expect (tolk.contains "slot_tag: uint64")
    "OptionState Tolk must declare slot_tag: uint64"
  expect (tolk.contains "slot_p0: uint64")
    "OptionState Tolk must declare slot_p0: uint64"
  expect (tolk.contains "get fun peek()")
    "OptionState Tolk must declare peek get-method"
  expect (tolk.contains "get fun getOpt(): (int, int)")
    "OptionState Tolk must declare 2-leaf tuple return for getOpt"
  expect (tolk.contains "return (")
    "OptionState Tolk must emit multi-value return ("
  let abi ← findFile files "OptionState.ton-abi.json"
  expect (abi.contains "slot_tag" && abi.contains "slot_p0")
    s!"OptionState ABI must declare slot_tag/slot_p0, got: {abi}"
  expect (abi.contains "\"returns\":[\"uint64\",\"uint64\"]")
    s!"OptionState ABI must declare getOpt [\"uint64\",\"uint64\"], got: {abi}"
  -- Locked tolk → real .fif (host-optional only when tool root + stdlib present).
  let home ← IO.getEnv "HOME"
  let toolRoot ← match ← IO.getEnv "PROOF_FORGE_TOOL_ROOT" with
    | some r => pure r
    | none =>
        match home with
        | some h => pure s!"{h}/.cache/proof-forge-v2/tool-root/darwin-arm64"
        | none => pure ""
  let stdlib ← match ← IO.getEnv "PROOF_FORGE_TOLK_STDLIB" with
    | some p => pure p
    | none =>
        match ← IO.getEnv "PROOF_FORGE_TON_TOOLS" with
        | some root => pure s!"{root}/tolk-stdlib"
        | none =>
            match home with
            | some h => pure s!"{h}/.cache/proof-forge-v2/ton-tools/tolk-stdlib"
            | none => pure ""
  let tolkBin := System.FilePath.mk (toolRoot ++ "/tolk")
  let stdlibPath := System.FilePath.mk stdlib
  if (← tolkBin.pathExists) && (← stdlibPath.pathExists) then
    let tmp ← IO.Process.output {
      cmd := "mktemp"
      args := #["-d", "/tmp/pf-ton-option-state.XXXXXX"]
    }
    unless tmp.exitCode == 0 do
      throw <| IO.userError s!"mktemp failed: {tmp.stderr}"
    let staging := (tmp.stdout.trim)
    try
      IO.FS.writeFile (System.FilePath.mk staging / "OptionState.tolk") tolk
      let proc ← IO.Process.output {
        cmd := tolkBin.toString
        args := #["-o", "OptionState.fif", "OptionState.tolk"]
        cwd := some (System.FilePath.mk staging)
        env := #[("TOLK_STDLIB", stdlib), ("LC_ALL", "C"), ("TZ", "UTC")]
      }
      unless proc.exitCode == 0 do
        throw <| IO.userError
          s!"locked tolk failed to compile OptionState.tolk:\n{proc.stderr}{proc.stdout}"
      let fifPath := System.FilePath.mk staging / "OptionState.fif"
      unless ← fifPath.pathExists do
        throw <| IO.userError "tolk returned no OptionState.fif"
      let fifBytes ← IO.FS.readFile fifPath
      expect (fifBytes.length > 0) "OptionState.fif must be non-empty"
      IO.println "  ✓ OptionState locked tolk → .fif"
    finally
      let _ ← IO.Process.output {
        cmd := "rm"
        args := #["-rf", staging]
      }
  else
    IO.println "  · OptionState tolk→fif skipped (tool-root/tolk or stdlib absent)"
  IO.println "  ✓ OptionState Option UInt64 state Plan/IR/Tolk pin"

/-- B-CTX-OPEN (BL-38): `context.unixTimeSeconds` lowers on TON to Tolk
    `blockchain.now()` (Plan Expr tag 51 / `blockUnixTimeSeconds`);
    `context.caller` and unknown ContextRead keys stay fail closed. Locked
    tolk → .fif when tool-root + stdlib are present (same optional path as
    OptionState). -/
private unsafe def testContextReadUnixTime
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrapProgram "ClockBox" <|
    "  state t : UInt64\n\n" ++
    "  init() do\n" ++
    "    t := 0\n\n" ++
    "  entry stamp() : UInt64 do\n" ++
    "    t := context.unixTimeSeconds\n" ++
    "    return t\n\n" ++
    "  view last() : UInt64 do\n" ++
    "    return t\n\n" ++
    "  view peekNow() : UInt64 do\n" ++
    "    return context.unixTimeSeconds\n"
  let compiled ← compileSource session source "Examples.ClockBox" "<ton-clock-box>"
  let plan ← liftResult (planTon compiled)
  -- (a) Plan body: stamp stores blockUnixTimeSeconds; peekNow returns it.
  let stamp ← findMethod plan "stamp"
  let hasTsStore := stamp.body.any fun s =>
    match s with
    | .store op =>
        match op.value with
        | .blockUnixTimeSeconds => true
        | _ => false
    | _ => false
  expect hasTsStore "ClockBox: stamp must store blockUnixTimeSeconds"
  let peekNow ← findMethod plan "peekNow"
  let hasTsRet := peekNow.body.any fun s =>
    match s with
    | .returnValue .blockUnixTimeSeconds => true
    | _ => false
  expect hasTsRet "ClockBox: peekNow must return blockUnixTimeSeconds"
  match validatePlan plan with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"ClockBox plan must validate: {e.render}"
  -- IR carries the op on both entry and view paths.
  let ir ← liftResult (irTon compiled)
  let stampIR ← findMethodIR ir "stamp"
  expect (stampIR.operations.any fun
      | .blockUnixTimeSeconds _ => true
      | _ => false)
    "ClockBox stamp IR must carry blockUnixTimeSeconds"
  let peekIR ← findMethodIR ir "peekNow"
  expect (peekIR.operations.any fun
      | .blockUnixTimeSeconds _ => true
      | _ => false)
    "ClockBox peekNow IR must carry blockUnixTimeSeconds (view path)"
  -- (b) Emitted Tolk contains blockchain.now() on both method bodies.
  let files ← liftResult (filesTon compiled)
  let tolk ← findFile files "ClockBox.tolk"
  expect (tolk.contains "blockchain.now()")
    "ClockBox Tolk must contain blockchain.now()"
  expect (tolk.contains "fun onInternalMessage" || tolk.contains "onInternalMessage")
    "ClockBox Tolk must keep onInternalMessage entry surface"
  expect (tolk.contains "get fun last()" || tolk.contains "get fun peekNow()")
    "ClockBox Tolk must declare a get-method view"
  -- stamp (entry) + peekNow (view) each emit blockchain.now() → ≥ 2.
  let nowCount := (tolk.splitOn "blockchain.now()").length - 1
  expect (nowCount >= 2)
    s!"ClockBox Tolk must emit blockchain.now() in entry and view (got {nowCount})"
  -- (c) Locked tolk → real .fif (host-optional; same pattern as OptionState).
  let home ← IO.getEnv "HOME"
  let toolRoot ← match ← IO.getEnv "PROOF_FORGE_TOOL_ROOT" with
    | some r => pure r
    | none =>
        match home with
        | some h => pure s!"{h}/.cache/proof-forge-v2/tool-root/darwin-arm64"
        | none => pure ""
  let stdlib ← match ← IO.getEnv "PROOF_FORGE_TOLK_STDLIB" with
    | some p => pure p
    | none =>
        match ← IO.getEnv "PROOF_FORGE_TON_TOOLS" with
        | some root => pure s!"{root}/tolk-stdlib"
        | none =>
            match home with
            | some h => pure s!"{h}/.cache/proof-forge-v2/ton-tools/tolk-stdlib"
            | none => pure ""
  let tolkBin := System.FilePath.mk (toolRoot ++ "/tolk")
  let stdlibPath := System.FilePath.mk stdlib
  if (← tolkBin.pathExists) && (← stdlibPath.pathExists) then
    let tmp ← IO.Process.output {
      cmd := "mktemp"
      args := #["-d", "/tmp/pf-ton-clock-box.XXXXXX"]
    }
    unless tmp.exitCode == 0 do
      throw <| IO.userError s!"mktemp failed: {tmp.stderr}"
    let staging := (tmp.stdout.trim)
    try
      IO.FS.writeFile (System.FilePath.mk staging / "ClockBox.tolk") tolk
      let proc ← IO.Process.output {
        cmd := tolkBin.toString
        args := #["-o", "ClockBox.fif", "ClockBox.tolk"]
        cwd := some (System.FilePath.mk staging)
        env := #[("TOLK_STDLIB", stdlib), ("LC_ALL", "C"), ("TZ", "UTC")]
      }
      unless proc.exitCode == 0 do
        throw <| IO.userError
          s!"locked tolk failed to compile ClockBox.tolk:\n{proc.stderr}{proc.stdout}"
      let fifPath := System.FilePath.mk staging / "ClockBox.fif"
      unless ← fifPath.pathExists do
        throw <| IO.userError "tolk returned no ClockBox.fif"
      let fifBytes ← IO.FS.readFile fifPath
      expect (fifBytes.length > 0) "ClockBox.fif must be non-empty"
      IO.println "  ✓ ClockBox locked tolk → .fif"
    finally
      let _ ← IO.Process.output {
        cmd := "rm"
        args := #["-rf", staging]
      }
  else
    IO.println "  · ClockBox tolk→fif skipped (tool-root/tolk or stdlib absent)"
  -- (d) context.caller stays fail closed. TON type-closure is
  -- `pilotPrincipalPolicyNone`, so Principal from `context.caller` is rejected
  -- at type closure (message cites Principal) before the ContextRead arm —
  -- still fail closed. LowerSemantic keeps an explicit ContextRead/caller arm
  -- for defense-in-depth if Principal storage is later admitted.
  let callerSrc := wrapProgram "CallerBox" <|
    "  entry who() : UInt64 do\n" ++
    "    let c : Principal := context.caller\n" ++
    "    return 0\n"
  let clCompiled ← compileSource session callerSrc "Examples.CallerBox"
    "<ton-caller-box>"
  match planTon clCompiled with
  | .error e =>
      expect (e.render.contains "ContextRead" || e.render.contains "caller" ||
          e.render.contains "Principal")
        s!"caller FC must cite ContextRead/caller/Principal boundary, got: {e.render}"
  | .ok _ =>
      throw <| IO.userError "TON context.caller must fail closed"
  -- (e) ADR-0031 S2: shared admits `context.blockHeight`, but TON Plan keeps
  -- it fail closed (no honest TON height binding). Needs a state leaf so
  -- profile state-count gates do not mask the ContextRead arm.
  let heightSrc := wrapProgram "HeightBox" <|
    "  state pad : UInt64\n" ++
    "  init() do\n" ++
    "    pad := 0\n" ++
    "  entry height() : UInt64 do\n" ++
    "    return context.blockHeight\n" ++
    "  view get() : UInt64 do\n" ++
    "    return pad\n"
  let hCompiled ← compileSource session heightSrc "Examples.HeightBox"
    "<ton-height-box>"
  match planTon hCompiled with
  | .error e =>
      expect (e.render.contains "ContextRead" || e.render.contains "context" ||
          e.render.contains "block-height" || e.render.contains "blockHeight")
        s!"TON blockHeight Plan FC must cite ContextRead/context/blockHeight, got: {e.render}"
  | .ok _ =>
      throw <| IO.userError "TON context.blockHeight must fail closed at Plan"
  -- (e2) SYS-S4: attachedValue / chainId have no TON host. Pin the named
  -- Plan diagnostic (unixTime lowering is unchanged).
  let attachedSrc := wrapProgram "AttachedBox" <|
    "  state pad : UInt64\n" ++
    "  init() do\n" ++
    "    pad := 0\n" ++
    "  entry take() : UInt64 do\n" ++
    "    return context.attachedValue\n" ++
    "  view get() : UInt64 do\n" ++
    "    return pad\n"
  let aCompiled ← compileSource session attachedSrc "Examples.AttachedBox"
    "<ton-attached-box>"
  match planTon aCompiled with
  | .error e =>
      expect (e.render.contains "has no Ton host binding")
        s!"TON attachedValue Plan FC must contain 'has no Ton host binding', got: {e.render}"
      expect (e.render.contains "attached-value" || e.render.contains "attachedValue")
        s!"TON attachedValue Plan FC must name attachedValue, got: {e.render}"
  | .ok _ =>
      throw <| IO.userError "TON context.attachedValue must fail closed at Plan"
  let chainSrc := wrapProgram "ChainBox" <|
    "  state pad : UInt64\n" ++
    "  init() do\n" ++
    "    pad := 0\n" ++
    "  entry cid() : UInt64 do\n" ++
    "    return context.chainId\n" ++
    "  view get() : UInt64 do\n" ++
    "    return pad\n"
  let cidCompiled ← compileSource session chainSrc "Examples.ChainBox"
    "<ton-chain-box>"
  match planTon cidCompiled with
  | .error e =>
      expect (e.render.contains "has no Ton host binding")
        s!"TON chainId Plan FC must contain 'has no Ton host binding', got: {e.render}"
      expect (e.render.contains "chain-id" || e.render.contains "chainId")
        s!"TON chainId Plan FC must name chainId, got: {e.render}"
  | .ok _ =>
      throw <| IO.userError "TON context.chainId must fail closed at Plan"
  -- (e3) context.self (source spelling `context.contractId`; wire key
  -- `proof-forge.context.self.v1`) is Principal. TON type-closure is
  -- `pilotPrincipalPolicyNone`, so Principal is rejected at type closure
  -- before the ContextRead/self arm — still fail closed. LowerSemantic
  -- keeps an explicit self arm (same as caller) for defense-in-depth.
  let selfSrc := wrapProgram "SelfBox" <|
    "  entry who() : UInt64 do\n" ++
    "    let s : Principal := context.contractId\n" ++
    "    return 0\n"
  let sCompiled ← compileSource session selfSrc "Examples.SelfBox"
    "<ton-self-box>"
  match planTon sCompiled with
  | .error e =>
      expect (e.render.contains "ContextRead" || e.render.contains "self" ||
          e.render.contains "Principal")
        s!"self FC must cite ContextRead/self/Principal boundary, got: {e.render}"
  | .ok _ =>
      throw <| IO.userError "TON context.self must fail closed"
  -- (f) Truly unknown context key still FC at Normalize (closed catalog).
  let unknownSrc := wrapProgram "UnknownCtx" <|
    "  state pad : UInt64\n" ++
    "  init() do\n" ++
    "    pad := 0\n" ++
    "  entry go() : UInt64 do\n" ++
    "    return context.notARealKey\n" ++
    "  view get() : UInt64 do\n" ++
    "    return pad\n"
  match ← session.selectProgramV1 unknownSrc
      "<ton-unknown-ctx>" "Examples.UnknownCtx" none with
  | .error e =>
      expect (e.render.contains "context" || e.render.contains "Context" ||
          e.render.contains "notARealKey" || e.render.contains "unsupported")
        s!"unknown context key must cite context boundary at select, got: {e.render}"
  | .ok validated =>
      match Compiler.compileValidatedSourceV1 validated with
      | .error e =>
          expect (e.render.contains "context" || e.render.contains "Context" ||
              e.render.contains "unsupported" || e.render.contains "notARealKey")
            s!"unknown context key must fail closed citing context, got: {e.render}"
      | .ok compiled =>
          match planTon compiled with
          | .error e =>
              expect (e.render.contains "ContextRead" || e.render.contains "context")
                s!"unknown ContextRead plan FC must cite ContextRead/context, got: {e.render}"
          | .ok _ =>
              throw <| IO.userError
                "unknown context key must fail closed (Normalize or Plan)"
  IO.println "  ✓ B-CTX-OPEN unixTimeSeconds → blockchain.now(); caller/self/blockHeight/attachedValue/chainId/unknown FC"

/-- SYS-E2: TON has no native vault host. `pf.assets.native.balanceOfSelf`
    stays Plan fail closed. Product `planTon` still declines
    `extension.pf-assets` at resolve, so this pin uses the same engineering
    Plan path as the crypto pins (compile reaches Plan). unixTime
    ContextRead remains admitted. -/
private unsafe def testEnvReadNativeStayFailClosed
    (session : Language.Loader.ParserSession) : IO Unit := do
  let src := wrapProgram "EnvReadBalanceTon" <|
    "  requires extension pf.assets version \"1.1.0\"\n" ++
      "    digest \"sha256:59412f732e634b0256a02c9ec23a253c38478879d6b74b279e750b220879aaa9\"\n\n" ++
      "  state count : UInt64\n\n" ++
      "  init(initial : UInt64) do\n" ++
      "    count := initial\n\n" ++
      "  view nativeBalance() : UInt64 do\n" ++
      "    return pf.assets.native.balanceOfSelf()\n\n" ++
      "  entry setCount(newCount : UInt64) : UInt64 do\n" ++
      "    count := newCount\n" ++
      "    return count\n"
  let compiled ← compileSource session src "Examples.EnvReadBalanceTon"
    "<ton-env-read-native>"
  match engineeringPlanFromCompiled compiled with
  | .error e =>
      expect (e.render.contains "has no Ton host binding")
        s!"EnvReadBalanceTon Plan FC must contain 'has no Ton host binding', got: {e.render}"
      expect (e.render.contains "nativeVaultBalance")
        s!"EnvReadBalanceTon Plan FC must name nativeVaultBalance, got: {e.render}"
  | .ok _ =>
      throw <| IO.userError
        "EnvReadBalanceTon must Plan fail closed (no Ton vault host)"
  IO.println "  ✓ envRead nativeVaultBalance stay fail closed (no Ton host)"

/-- TON-1a: grammar-valid but unregistered profile stays unknown.
    Do not invent a second TON CodegenProfileId. -/
unsafe def testUnknownProfileFailClosed : IO Unit := do
  match CodegenProfileId.parse? "not-a-real-profile-v1" with
  | none =>
      throw <| IO.userError "not-a-real-profile-v1 must remain grammar-valid"
  | some unknown =>
      match resolveBuildSelectionV1 TargetId.ton (some unknown) with
      | .error e =>
          expect (e.code == "PF-PROFILE-UNKNOWN")
            s!"unknown TON profile must be PF-PROFILE-UNKNOWN, got {e.code}: {e.render}"
      | .ok sel =>
          throw <| IO.userError
            s!"unknown TON profile must fail closed, got {sel.codegenProfile}"
  IO.println "  ✓ unknown profile fail closed"

unsafe def run : IO Unit := do
  IO.println "TonPlanV1"
  let session ← Tests.Language.ParserSession.shared
  testStateCellPlan session
  testStateCellIRAndTolk session
  testMultiField session
  testCallSyncFc session
  testResultBearingExternalCallFailClosed
  testCryptoSha256StayFailClosed session
  testSchedulePlanAndTolk session
  testNarrowUInt8 session
  testNarrowUInt16UInt32 session
  testNarrowInt8 session
  testNarrowInt16Int32 session
  testSignedContainerFc session
  testMultiWidthFc session
  testRegistryDispatch session
  testNamedStructReturn session
  testNamedEnumReturn session
  testAnonymousArrayReturn session
  testAnonymousOptionReturn session
  testOptionState session
  testAggregateFailClosed session
  testContextReadUnixTime session
  testEnvReadNativeStayFailClosed session
  testUnknownProfileFailClosed
  IO.println "TonPlanV1: all checks passed"

end Tests.Materialization.TonPlanV1
