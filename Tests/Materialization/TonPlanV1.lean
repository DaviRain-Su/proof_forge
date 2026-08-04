/-
  Ton Plan/IR/Tolk engineering suite (TON-2 Counter leaf + BL-1 schedule +
  BL-10 named aggregate view returns + BL-23 anonymous Array/Option view
  returns).

  Pins Counter plan shape, Tolk surface (Storage/onInternalMessage/get fun),
  op+query_id envelope, UInt64 range-check markers, schedule→createMessage
  out-message emission (dest hash stub / NoBounce / value=0 /
  PAY_FEES_SEPARATELY / op32·query_id·args body), BL-14 multi-width
  UInt{8,16,32} body/state/param (narrow guards + exact cell/param widths),
  B-RET-ABI named Struct/Enum view multi-stack returns, N-ANON-RESULT
  anonymous Array UInt64 N / Option UInt64 view returns (entry aggregate FC),
  and explicit fail-closed boundaries (sync call, UInt128/256, Map/Bytes
  returns, N>8, nested/narrow-element containers, invariants, Field/Principal).

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
  -- Counter shapes remain intact: no schedule on Counter
  let counter ← compileSource session counterSourceText counterModuleName
    "<ton-counter-sched-reg>"
  let cPlan ← liftResult <| planTon counter
  expect (!planUsesPromiseV1 cPlan) "Counter plan has no schedule"
  let cFiles ← liftResult <| filesTon counter
  let cTolk ← findFile cFiles "Counter.tolk"
  expect (!cTolk.contains "createMessage({") "Counter.tolk has no createMessage"
  expect (cTolk.contains "struct Storage") "Counter Storage preserved"
  expect (cTolk.contains "fun onInternalMessage") "Counter entry preserved"
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
  -- Historical UInt64 Counter surface still uses (1 << 64); mix must not drop it
  -- when absent — pin only that narrow bounds are present.
  let abi ← findFile files "NarrowMix.ton-abi.json"
  expect (abi.contains "\"type\":\"uint16\"") "ABI uint16"
  expect (abi.contains "\"type\":\"uint32\"") "ABI uint32"
  IO.println "  ✓ UInt16/UInt32 state/param/body + exact cell widths"

/-- BL-14: UInt128/256 and Int8 stay fail closed. -/
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
  -- Int8 (narrow signed beyond Int64)
  let srcI8 := wrapProgram "NarrowI8" <|
    "  state s : Int8\n\n" ++
    "  init(x : Int8) do\n" ++
    "    s := x\n\n" ++
    "  entry go(d : Int8) : Int8 do\n" ++
    "    s := s + d\n" ++
    "    return s\n\n" ++
    "  view peek() : Int8 do\n" ++
    "    return s\n"
  match ← (do
      try
        let c ← compileSource session srcI8 "Examples.NarrowI8" "<ton-i8-fc>"
        pure (some c)
      catch _ => pure none) with
  | none => pure ()
  | some c =>
      match planTon c with
      | .error _ => pure ()
      | .ok _ => throw <| IO.userError "Int8: expected FC, got ok"
  IO.println "  ✓ UInt128/256 + Int8 fail closed"

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
  IO.println "  ✓ aggregate return fail-closed boundaries (entry/Map/Bytes/9-leaf/nested)"

unsafe def run : IO Unit := do
  IO.println "TonPlanV1"
  let session ← Tests.Language.ParserSession.shared
  testCounterPlan session
  testCounterIRAndTolk session
  testMultiField session
  testCallSyncFc session
  testSchedulePlanAndTolk session
  testNarrowUInt8 session
  testNarrowUInt16UInt32 session
  testMultiWidthFc session
  testRegistryDispatch session
  testNamedStructReturn session
  testNamedEnumReturn session
  testAnonymousArrayReturn session
  testAnonymousOptionReturn session
  testAggregateFailClosed session
  IO.println "TonPlanV1: all checks passed"

end Tests.Materialization.TonPlanV1
