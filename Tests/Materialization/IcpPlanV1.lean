/-
  ICP Plan/IR/WAT engineering suite (ICP-2 Counter/StateCell leaf, ADR-0047).

  Pins StateCell plan shape (public UInt64 state, init/entry(mutate)/view,
  checked add/sub), IR/wat/.did surface (ic0 imports, mutable i64 state globals,
  DIDL/LEB128 header handling, canister_init/canister_update/canister_query
  exports, Candid nat64 service), registry materialize dispatch, and explicit
  fail-closed boundaries (sync call, emit, schedule, nonempty invariant,
  aggregates/multi-width).

  Registered via Tests/Shards/Targets. Materialize is zero-tool; Finalize
  is locked wat2wasm (ICP-1a). Not a PocketIC/dfx/replica lane; not formal D4.
-/
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Targets.Icp
import ProofForgeV2.Targets.Registry
import ProofForgeV2.Targets.BuildSelectionV1
import ProofForgeV2.Language.Loader
import Tests.Language.ParserSession

namespace Tests.Materialization.IcpPlanV1

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Targets.BuildSelectionV1
open ProofForgeV2.Targets.Icp

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
  | .error (.planInvariant .icp msg) =>
      expect (msg.contains needle)
        s!"{label}: expected message containing '{needle}', got '{msg}'"
  | .error e => throw <| IO.userError s!"{label}: expected icp planInvariant, got {e.render}"
  | .ok _ => throw <| IO.userError s!"{label}: expected failure, got ok"

private unsafe def compileSource (session : Language.Loader.ParserSession)
    (source moduleName path : String) : IO CompiledSemanticV1 := do
  let validated ← liftResult (← session.selectProgramV1 source path moduleName none)
  liftResult <| Compiler.compileValidatedSourceV1 validated

private def icpCapability (compiled : CompiledSemanticV1) :
    CompileResult Targets.ResolvedEngineeringBuildV1 := do
  let selection ← resolveBuildSelectionV1 TargetId.icp none
  Targets.resolveEngineeringRequirementsV1 selection compiled

private def planIcp (compiled : CompiledSemanticV1) : CompileResult Plan := do
  let capability ← icpCapability compiled
  planFromCapability capability

private def irIcp (compiled : CompiledSemanticV1) : CompileResult IR := do
  let capability ← icpCapability compiled
  irFromCapability capability

private def filesIcp (compiled : CompiledSemanticV1) : CompileResult (Array OutputFile) := do
  let capability ← icpCapability compiled
  buildFromCapability capability

private def findFile (files : Array OutputFile) (path : String) : IO String :=
  match files.find? (·.path == path) with
  | some file => pure file.contents
  | none => throw <| IO.userError s!"missing output file '{path}'; got {files.map (·.path)}"

private def findMethod (plan : Plan) (name : String) : IO Method :=
  match plan.entries.find? (·.name == name) with
  | some m => pure m
  | none =>
      match plan.views.find? (·.name == name) with
      | some m => pure m
      | none => throw <| IO.userError s!"missing method '{name}'"

private unsafe def testStateCellPlan
    (session : Language.Loader.ParserSession) : IO Unit := do
  let compiled ← compileSource session stateCellSourceText stateCellModuleName "<icp-stateCell>"
  let plan ← liftResult <| planIcp compiled
  expect (plan.programName == "StateCell") "program name StateCell"
  expect (plan.states.size == 1) "one state field"
  expect (plan.states[0]!.name == "count") "state name count"
  expect (plan.initializer.name == "init") "init method"
  expect (plan.initializer.mode == .initialize) "init mode"
  expect (plan.initializer.resultKind == .unit) "init result Unit"
  expect (plan.initializer.params.size == 1) "init one param"
  expect (plan.entries.size == 1) "one entry"
  expect (plan.views.size == 1) "one view"
  let inc ← findMethod plan "increment"
  expect (inc.mode == .mutate && inc.resultKind == .uint64) "increment mutate UInt64"
  let hasStoreAdd := inc.body.any fun s =>
    match s with
    | .store 0 (.checkedAdd (.stateLoad 0) (.param 0)) => true
    | _ => false
  expect hasStoreAdd "increment stores checkedAdd(stateLoad 0, param 0)"
  let hasReturnLoad := inc.body.any fun s =>
    match s with
    | .returnValue (.stateLoad 0) => true
    | _ => false
  expect hasReturnLoad
    "increment returns stateLoad 0 after store (no store-then-read re-add)"
  let get ← findMethod plan "get"
  expect (get.mode == .query && get.resultKind == .uint64) "get view UInt64"
  expect (get.body == #[.returnValue (.stateLoad 0)]) "get returns stateLoad 0"
  match validatePlan plan with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"StateCell plan must validate: {e.render}"
  let d1 ← match engineeringIcpPlanDigestV1 plan with
    | .ok d => pure d
    | .error e => throw <| IO.userError e
  let d2 ← match engineeringIcpPlanDigestV1 plan with
    | .ok d => pure d
    | .error e => throw <| IO.userError e
  expect (d1 == d2) "plan digest deterministic"
  IO.println "  ✓ StateCell plan shape"

private unsafe def testStateCellIRAndWat
    (session : Language.Loader.ParserSession) : IO Unit := do
  let compiled ← compileSource session stateCellSourceText stateCellModuleName
    "<icp-stateCell-ir>"
  let ir ← liftResult <| irIcp compiled
  expect (ir.entries.size == 1) "one entry method"
  expect (ir.views.size == 1) "one view method"
  let files ← liftResult <| filesIcp compiled
  let wat ← findFile files "StateCell.wat"
  let did ← findFile files "StateCell.did"
  -- WAT surface: ic0 imports, memory export, state globals, method exports.
  expect (wat.contains "(module") "wat module header"
  expect (wat.contains "\"ic0\" \"msg_arg_data_size\"") "ic0 msg_arg_data_size import"
  expect (wat.contains "\"ic0\" \"msg_arg_data_copy\"") "ic0 msg_arg_data_copy import"
  expect (wat.contains "\"ic0\" \"msg_reply_data_append\"") "ic0 msg_reply_data_append import"
  expect (wat.contains "\"ic0\" \"msg_reply\"") "ic0 msg_reply import"
  expect (wat.contains "(memory (export \"memory\") 1)") "memory export"
  expect (wat.contains "(global $g_state_0 (mut i64) (i64.const 0)) ;; count")
    "state global for count"
  expect (wat.contains "(export \"canister_init\" (func $canister_init))")
    "canister_init export"
  expect (wat.contains "(export \"canister_update increment\" (func $increment))")
    "canister_update increment export"
  expect (wat.contains "(export \"canister_query get\" (func $get))")
    "canister_query get export"
  expect (wat.contains "i64.add") "checked add present"
  expect (wat.contains "unreachable") "overflow trap present"
  -- Honesty notes present.
  expect (wat.contains "MVP heap globals only") "MVP heap globals honesty note"
  expect (wat.contains "Candid nat64-only inline codec") "Candid pilot honesty note"
  -- No leakage from other targets.
  expect (!wat.contains "storage_read") "no NEAR storage_read"
  expect (!wat.contains "db_read") "no CosmWasm db_read"
  expect (!wat.contains "(module\n  (import \"env\"") "no TON/Solana-style env import"
  -- .did surface: nat64 args/results.
  expect (did.contains "service : (nat64) {") "did init arg nat64"
  expect (did.contains "increment : (nat64) -> (nat64);") "did increment signature"
  expect (did.contains "get : () -> (nat64) query;") "did get query signature"
  IO.println "  ✓ StateCell IR/wat/.did shape"

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
  let compiled ← compileSource session callSrc "Examples.CallFc" "<icp-call-fc>"
  -- Engineering Plan path pins the envelope message even if the product
  -- resolver declines effect.synchronous-call first.
  expectPlanErrorContaining "call plan" "call is outside the ICP-2 envelope"
    (planFromCompiledSemanticV1 compiled)
  IO.println "  ✓ call/sync fail closed"

/-- SYS-S5: ICP has no sha256/keccak256 host. Exact `pf.crypto.*` stays
    Plan fail closed (no host / precompile / circuit gadget). -/
private unsafe def testCryptoSha256StayFailClosed
    (session : Language.Loader.ParserSession) : IO Unit := do
  let expectPlanFc (programName pathLabel moduleName body needle : String) :
      IO Unit := do
    let src := wrapProgram programName body
    let compiled ← compileSource session src moduleName pathLabel
    match planFromCompiledSemanticV1 compiled with
    | .error e =>
        expect (e.render.contains needle)
          s!"{programName} Plan FC must contain '{needle}', got: {e.render}"
    | .ok _ =>
        throw <| IO.userError
          s!"{programName} must Plan fail closed (no Icp crypto host)"
  let cryptoBody (qn : String) : String :=
    "  state pad : UInt64\n\n" ++
      "  init() do\n" ++
      "    pad := 0\n\n" ++
      "  entry probe() : UInt64 do\n" ++
      "    let w : UInt64 := 0\n" ++
      "    let h : UInt64 := call " ++ qn ++ "(w)\n" ++
      "    return pad\n\n" ++
      "  view get() : UInt64 do\n" ++
      "    return pad\n"
  expectPlanFc "Sha256Icp" "<icp-sha256>" "Examples.Sha256Icp"
    (cryptoBody "pf.crypto.sha256") "has no Icp host binding"
  expectPlanFc "Keccak256Icp" "<icp-keccak256>" "Examples.Keccak256Icp"
    (cryptoBody "pf.crypto.keccak256") "has no Icp host binding"
  expectPlanFc "Sha256IcpHashNoPad" "<icp-sha256-hashnopad>"
    "Examples.Sha256IcpHashNoPad"
    (cryptoBody "pf.crypto.hashNoPad") "has no Icp host binding"
  IO.println "  ✓ pf.crypto.sha256/keccak256 stay fail closed (no Icp host)"

/-- SYS-S4: ICP has no unixTime/blockHeight/attachedValue/chainId host.
    Named UInt64 ContextRead keys stay Plan fail closed. caller/self are
    Principal and stay on the generic ContextRead envelope (ICP-2 rejects
    Principal at type closure first). -/
private unsafe def testContextReadStayFailClosed
    (session : Language.Loader.ParserSession) : IO Unit := do
  let expectPlanFc (programName pathLabel moduleName body needle schemaId : String) :
      IO Unit := do
    let src := wrapProgram programName body
    let compiled ← compileSource session src moduleName pathLabel
    match planFromCompiledSemanticV1 compiled with
    | .error e =>
        expect (e.render.contains needle)
          s!"{programName} Plan FC must contain '{needle}', got: {e.render}"
        expect (e.render.contains schemaId)
          s!"{programName} Plan FC must name '{schemaId}', got: {e.render}"
    | .ok _ =>
        throw <| IO.userError
          s!"{programName} must Plan fail closed (no Icp context host)"
  let ctxBody (place : String) : String :=
    "  state pad : UInt64\n\n" ++
      "  init() do\n" ++
      "    pad := 0\n\n" ++
      "  entry probe() : UInt64 do\n" ++
      "    return " ++ place ++ "\n\n" ++
      "  view get() : UInt64 do\n" ++
      "    return pad\n"
  expectPlanFc "UnixTimeIcp" "<icp-unix-time>" "Examples.UnixTimeIcp"
    (ctxBody "context.unixTimeSeconds") "has no Icp host binding"
    "proof-forge.context.unix-time-seconds.v1"
  expectPlanFc "BlockHeightIcp" "<icp-block-height>" "Examples.BlockHeightIcp"
    (ctxBody "context.blockHeight") "has no Icp host binding"
    "proof-forge.context.block-height.v1"
  expectPlanFc "AttachedValueIcp" "<icp-attached-value>" "Examples.AttachedValueIcp"
    (ctxBody "context.attachedValue") "has no Icp host binding"
    "proof-forge.context.attached-value.v1"
  expectPlanFc "ChainIdIcp" "<icp-chain-id>" "Examples.ChainIdIcp"
    (ctxBody "context.chainId") "has no Icp host binding"
    "proof-forge.context.chain-id.v1"
  IO.println "  ✓ context UInt64 keys stay fail closed (no Icp host)"

/-- SYS-E2: ICP has no native vault host. `pf.assets.native.balanceOfSelf`
    stays Plan fail closed. token/U128 stay on the generic envRead envelope
    (Principal mint / UInt128 rejected first). -/
private unsafe def testEnvReadNativeStayFailClosed
    (session : Language.Loader.ParserSession) : IO Unit := do
  let src := wrapProgram "EnvReadBalanceIcp" <|
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
  let compiled ← compileSource session src "Examples.EnvReadBalanceIcp"
    "<icp-env-read-native>"
  match planFromCompiledSemanticV1 compiled with
  | .error e =>
      expect (e.render.contains "has no Icp host binding")
        s!"EnvReadBalanceIcp Plan FC must contain 'has no Icp host binding', got: {e.render}"
      expect (e.render.contains "envRead" || e.render.contains "nativeVaultBalance")
        s!"EnvReadBalanceIcp Plan FC must name envRead/nativeVaultBalance, got: {e.render}"
  | .ok _ =>
      throw <| IO.userError
        "EnvReadBalanceIcp must Plan fail closed (no Icp vault host)"
  IO.println "  ✓ envRead nativeVaultBalance stay fail closed (no Icp host)"

private unsafe def testEmitFc
    (session : Language.Loader.ParserSession) : IO Unit := do
  let emitSrc := wrapProgram "EmitFc" <|
    "  event Ping()\n\n" ++
    "  state s : UInt64\n\n" ++
    "  init(x : UInt64) do\n" ++
    "    s := x\n\n" ++
    "  entry go() : UInt64 do\n" ++
    "    emit Ping()\n" ++
    "    return s\n\n" ++
    "  view peek() : UInt64 do\n" ++
    "    return s\n"
  let compiled ← compileSource session emitSrc "Examples.EmitFc" "<icp-emit-fc>"
  match icpCapability compiled with
  | .error _ => pure ()  -- resolver FC on effect.event (ADR-0047 declines portable emit)
  | .ok capability =>
      expectPlanErrorContaining "emit plan" "emit" (planFromCapability capability)
  IO.println "  ✓ emit fail closed"

private unsafe def testInvariantFc
    (session : Language.Loader.ParserSession) : IO Unit := do
  let invSrc := wrapProgram "InvFc" <|
    "  state s : UInt64\n\n" ++
    "  init(x : UInt64) do\n" ++
    "    s := x\n\n" ++
    "  entry go(d : UInt64) : UInt64 do\n" ++
    "    s := s + d\n" ++
    "    return s\n\n" ++
    "  view peek() : UInt64 do\n" ++
    "    return s\n\n" ++
    "  invariant nonNeg : true\n"
  let validated ← liftResult (← session.selectProgramV1 invSrc
    "<icp-inv-fc>" "Examples.InvFc" none)
  match Compiler.compileValidatedSourceV1 validated with
  | .error _ => pure ()
  | .ok compiled =>
      match icpCapability compiled with
      | .error _ => pure ()
      | .ok capability =>
          expectPlanErrorContaining "invariant plan" "invariant" (planFromCapability capability)
  IO.println "  ✓ nonempty invariant fail closed"

private unsafe def testScheduleFc
    (session : Language.Loader.ParserSession) : IO Unit := do
  let schedSrc := wrapProgram "SchedFc" <|
    "  state s : UInt64\n\n" ++
    "  init(x : UInt64) do\n" ++
    "    s := x\n\n" ++
    "  entry go() : UInt64 do\n" ++
    "    schedule ledger.daily(s)\n" ++
    "    return s\n\n" ++
    "  view peek() : UInt64 do\n" ++
    "    return s\n"
  let compiled ← compileSource session schedSrc "Examples.SchedFc" "<icp-sched-fc>"
  match icpCapability compiled with
  | .error _ => pure ()  -- resolver may FC on the schedule receiver stub shape
  | .ok capability =>
      expectPlanErrorContaining "schedule plan" "schedule" (planFromCapability capability)
  IO.println "  ✓ schedule (async) fail closed"

private unsafe def testAggregateFc
    (session : Language.Loader.ParserSession) : IO Unit := do
  let aggSrc := wrapProgram "AggFc" <|
    "  struct Pair where\n" ++
    "    a : UInt64\n" ++
    "    b : UInt64\n" ++
    "  state p : Pair\n\n" ++
    "  init(x : UInt64, y : UInt64) do\n" ++
    "    p := Pair.new(x, y)\n\n" ++
    "  entry go() : UInt64 do\n" ++
    "    return p.a\n\n" ++
    "  view peek() : UInt64 do\n" ++
    "    return p.a\n"
  match ← (do
      try
        let c ← compileSource session aggSrc "Examples.AggFc" "<icp-agg-fc>"
        pure (some c)
      catch _ => pure none) with
  | none => pure ()  -- may fail earlier at Normalize/typed
  | some compiled =>
      match planIcp compiled with
      | .error _ => pure ()
      | .ok _ => throw <| IO.userError "ICP aggregate state must fail closed"
  IO.println "  ✓ aggregate state fail closed"

private unsafe def testRegistryDispatch
    (session : Language.Loader.ParserSession) : IO Unit := do
  let compiled ← compileSource session stateCellSourceText stateCellModuleName
    "<icp-registry>"
  let capability ← liftResult <| icpCapability compiled
  let artifacts ← liftResult <| Targets.materializeResult capability
  expect (MaterializedArtifactsV1.artifactProgramNameOf artifacts == "StateCell")
    "registry materialize program name"
  let files := MaterializedArtifactsV1.filesOf artifacts
  expect (files.any (·.path == "StateCell.wat")) "registry emits .wat"
  expect (files.any (·.path == "StateCell.did")) "registry emits .did"
  IO.println "  ✓ Registry materialize dispatch"

/-- ICP-1a: product capability → materialize → locked wat2wasm Finalize.
    Write base files into a temp staging dir first; wat2wasm runs inside
    that dir. PocketIC/dfx/replica are not invoked. Tool Lock `wat2wasm`
    is required — do not skip-clean if it is missing. -/
private unsafe def testCapabilityProductPath
    (session : Language.Loader.ParserSession) : IO Unit := do
  let compiled ← compileSource session stateCellSourceText stateCellModuleName
    "<icp-finalize>"
  let selection ← liftResult <| resolveBuildSelectionV1 TargetId.icp none
  expect (selection.codegenProfile == CodegenProfileId.icpWasmCandidU64V1)
    "ICP selection must bind icp-wasm-candid-u64-v1"
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
      "ICP locked wat2wasm finalization must be deployable"
    expect (FinalizedArtifactsV1.extraFilesOf finalized == #["StateCell.wasm"])
      "ICP locked finalization must add exactly StateCell.wasm"
    let note := FinalizedArtifactsV1.evidenceNoteOf finalized
    expect (note.contains "wat2wasm")
      s!"ICP Finalize evidence must cite wat2wasm, got: {note}"
    expect (note.contains "PocketIC")
      s!"ICP Finalize evidence must cite PocketIC (not invoked), got: {note}"
    let wasm ← IO.FS.readBinFile (stagingDir / "StateCell.wasm")
    expect (wasm.size >= 8 && wasm[0]! == 0x00 && wasm[1]! == 0x61 &&
        wasm[2]! == 0x73 && wasm[3]! == 0x6d && wasm[4]! == 0x01 &&
        wasm[5]! == 0x00 && wasm[6]! == 0x00 && wasm[7]! == 0x00)
      "StateCell.wasm must carry Wasm magic/version 00 61 73 6d 01 00 00 00"
  IO.println "  ✓ capability product Finalize (locked wat2wasm)"

/-- ICP-1a: grammar-valid but unregistered profile stays unknown.
    Do not invent a reserved extra ICP profile id. -/
private unsafe def testUnknownProfileFailClosed : IO Unit := do
  match CodegenProfileId.parse? "not-a-real-profile-v1" with
  | none =>
      throw <| IO.userError "not-a-real-profile-v1 must remain grammar-valid"
  | some unknown =>
      match resolveBuildSelectionV1 TargetId.icp (some unknown) with
      | .error e =>
          expect (e.code == "PF-PROFILE-UNKNOWN")
            s!"unknown ICP profile must be PF-PROFILE-UNKNOWN, got {e.code}: {e.render}"
      | .ok sel =>
          throw <| IO.userError
            s!"unknown ICP profile must fail closed, got {sel.codegenProfile}"
  IO.println "  ✓ unknown profile fail closed"

unsafe def run : IO Unit := do
  IO.println "IcpPlanV1"
  let session ← Tests.Language.ParserSession.shared
  testStateCellPlan session
  testStateCellIRAndWat session
  testCallSyncFc session
  testCryptoSha256StayFailClosed session
  testContextReadStayFailClosed session
  testEnvReadNativeStayFailClosed session
  testEmitFc session
  testInvariantFc session
  testScheduleFc session
  testAggregateFc session
  testRegistryDispatch session
  testCapabilityProductPath session
  testUnknownProfileFailClosed
  IO.println "IcpPlanV1: all checks passed"

end Tests.Materialization.IcpPlanV1
