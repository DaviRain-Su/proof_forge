/-
  ICP Plan/IR/WAT engineering suite (ICP-2 Counter/StateCell leaf, ADR-0047).

  Pins StateCell plan shape (public UInt64 **or** homogeneous Int64 state,
  init/entry(mutate)/view, checked add/sub/mul/div/mod), IR/wat/.did surface (ic0 imports,
  mutable i64 state globals, DIDL/LEB128 header handling,
  canister_init/canister_update/canister_query exports, Candid nat64 or
  int64 service), registry materialize dispatch, and explicit fail-closed
  boundaries (sync call, emit, schedule, nonempty invariant,
  aggregates/mixed UInt64+Int64; Array UInt64 N∈1..8 flatten is admitted).
  CAP-1a admits `context.unixTimeSeconds` as
  `ic0.time` ns÷10⁹ on init/update/query; other UInt64 ContextRead keys stay
  named fail-closed.

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
  expect (plan.signedNumeric == false) "StateCell stays unsigned nat64"
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
  expect (ir.signedNumeric == false) "StateCell IR stays unsigned"
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
  expect (!wat.contains "\"ic0\" \"time\"")
    "StateCell must not import ic0.time (unixTime is use-gated)"
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
  expect (wat.contains "i64.lt_u") "unsigned overflow uses i64.lt_u"
  expect (!wat.contains "i64.shr_s") "unsigned StateCell must not emit signed overflow"
  expect (wat.contains "(i32.const 120)") "Candid nat64 opcode 0x78"
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

/-- Homogeneous Int64 StateCell: Candid `int64` (0x79) + signed overflow. -/
private unsafe def testInt64StateCell
    (session : Language.Loader.ParserSession) : IO Unit := do
  let src := wrapProgram "Int64Cell" <|
    "  state count : Int64\n\n" ++
    "  init(initial : Int64) do\n" ++
    "    count := initial\n\n" ++
    "  entry increment(delta : Int64) : Int64 do\n" ++
    "    count := count + delta\n" ++
    "    return count\n\n" ++
    "  entry decrement(delta : Int64) : Int64 do\n" ++
    "    count := count - delta\n" ++
    "    return count\n\n" ++
    "  view get() : Int64 do\n" ++
    "    return count\n"
  let compiled ← compileSource session src "Examples.Int64Cell" "<icp-int64-cell>"
  let plan ← liftResult <| planIcp compiled
  expect (plan.signedNumeric == true) "Int64Cell Plan is signed"
  expect (plan.states.size == 1) "one Int64 state"
  let inc ← findMethod plan "increment"
  expect (inc.resultKind == .int64) "increment result Int64"
  let dec ← findMethod plan "decrement"
  expect (dec.resultKind == .int64) "decrement result Int64"
  let get ← findMethod plan "get"
  expect (get.mode == .query && get.resultKind == .int64) "get view Int64"
  match validatePlan plan with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"Int64Cell plan must validate: {e.render}"
  let ir ← liftResult <| irIcp compiled
  expect (ir.signedNumeric == true) "Int64Cell IR is signed"
  let files ← liftResult <| filesIcp compiled
  let wat ← findFile files "Int64Cell.wat"
  let did ← findFile files "Int64Cell.did"
  expect (wat.contains "Candid int64 (0x79) inline codec")
    "signed honesty note"
  expect (wat.contains "(i32.const 121)") "Candid int64 opcode 0x79"
  expect (!wat.contains "(i32.const 120)") "signed program must not emit nat64 opcode"
  expect (wat.contains "i64.shr_s") "signed overflow inspects the sign bit"
  expect (wat.contains "i64.const 63") "sign-bit shift is 63"
  expect (!wat.contains "i64.lt_u") "signed overflow must not use unsigned lt_u"
  expect (wat.contains "(export \"canister_update increment\" (func $increment))")
    "signed increment export"
  expect (wat.contains "(export \"canister_update decrement\" (func $decrement))")
    "signed decrement export"
  expect (did.contains "service : (int64) {") "did init arg int64"
  expect (did.contains "increment : (int64) -> (int64);") "did increment int64"
  expect (did.contains "decrement : (int64) -> (int64);") "did decrement int64"
  expect (did.contains "get : () -> (int64) query;") "did get query int64"
  expect (!did.contains "nat64") "signed .did must not mention nat64"
  IO.println "  ✓ Int64Cell Plan/IR/wat/.did (Candid int64 + signed overflow)"

/-- Homogeneous UInt64 mul/div/mod emit checked Wasm ops. -/
private unsafe def testMulDivModAdmit
    (session : Language.Loader.ParserSession) : IO Unit := do
  let src := wrapProgram "Scale" <|
    "  state count : UInt64\n\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n\n" ++
    "  entry scale(factor : UInt64) : UInt64 do\n" ++
    "    count := count * factor / 3 + count % 3\n" ++
    "    return count\n\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let compiled ← compileSource session src "Examples.Scale" "<icp-scale>"
  let plan ← liftResult <| planIcp compiled
  expect (plan.signedNumeric == false) "Scale stays unsigned"
  match validatePlan plan with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"Scale plan must validate: {e.render}"
  let files ← liftResult <| filesIcp compiled
  let wat ← findFile files "Scale.wat"
  expect (wat.contains "i64.mul") "Scale WAT must emit i64.mul"
  expect (wat.contains "i64.div_u") "Scale WAT must emit i64.div_u"
  expect (wat.contains "i64.rem_u") "Scale WAT must emit i64.rem_u"
  expect (wat.contains "i64.eqz") "Scale WAT must trap on divisor 0"
  IO.println "  ✓ Scale mul/div/mod WAT"

/-- Signed Int64 mul emits i64.mul + reconstruction overflow trap. -/
private unsafe def testSignedMulAdmit
    (session : Language.Loader.ParserSession) : IO Unit := do
  let src := wrapProgram "I64Mul" <|
    "  state n : Int64\n\n" ++
    "  init(initial : Int64) do\n" ++
    "    n := initial\n\n" ++
    "  entry scale(factor : Int64) : Int64 do\n" ++
    "    n := n * factor\n" ++
    "    return n\n\n" ++
    "  view get() : Int64 do\n" ++
    "    return n\n"
  let compiled ← compileSource session src "Examples.I64Mul" "<icp-i64-mul>"
  let plan ← liftResult <| planIcp compiled
  expect (plan.signedNumeric == true) "I64Mul is signed"
  let files ← liftResult <| filesIcp compiled
  let wat ← findFile files "I64Mul.wat"
  expect (wat.contains "i64.mul") "signed mul WAT must emit i64.mul"
  expect (wat.contains "i64.div_s") "signed mul overflow uses i64.div_s"
  IO.println "  ✓ signed Int64 mul WAT"

/-- Bitwise NOT stays outside ICP-2. -/
private unsafe def testBitNotFc
    (session : Language.Loader.ParserSession) : IO Unit := do
  let src := wrapProgram "Mask" <|
    "  entry mask(value : UInt64) : UInt64 do\n" ++
    "    return ~value\n"
  let compiled ← compileSource session src "Examples.Mask" "<icp-bitnot>"
  expectPlanErrorContaining "bitNot" "op is outside"
    (planFromCompiledSemanticV1 compiled)
  IO.println "  ✓ bitNot fail closed"

/-- Mixing UInt64 and Int64 user-facing slots is fail closed. -/
private unsafe def testMixedInt64UInt64Fc
    (session : Language.Loader.ParserSession) : IO Unit := do
  let src := wrapProgram "MixInt64" <|
    "  state count : Int64\n\n" ++
    "  init(initial : Int64) do\n" ++
    "    count := initial\n\n" ++
    "  entry increment(delta : Int64) : Int64 do\n" ++
    "    count := count + delta\n" ++
    "    return count\n\n" ++
    "  view get() : UInt64 do\n" ++
    "    return 0\n"
  let compiled ← compileSource session src "Examples.MixInt64" "<icp-mix-int64>"
  expectPlanErrorContaining "mixed Int64/UInt64" "mixes"
    (planFromCompiledSemanticV1 compiled)
  IO.println "  ✓ mixed Int64/UInt64 fail closed"

/-- Resolver already advertises `value.bool`. Bool views/entries + comparisons. -/
private unsafe def testBoolPredicate
    (session : Language.Loader.ParserSession) : IO Unit := do
  let src := wrapProgram "BoolPredicate" <|
    "  state count : UInt64\n\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n\n" ++
    "  entry bump(delta : UInt64) : UInt64 do\n" ++
    "    count := count + delta\n" ++
    "    return count\n\n" ++
    "  view positive() : Bool do\n" ++
    "    return count > 0\n\n" ++
    "  entry equalsCount(delta : UInt64) : Bool do\n" ++
    "    return count == delta\n"
  let compiled ← compileSource session src "Examples.BoolPredicate" "<icp-bool>"
  let plan ← liftResult <| planIcp compiled
  expect (plan.signedNumeric == false) "BoolPredicate stays unsigned"
  let pos ← findMethod plan "positive"
  expect (pos.mode == .query && pos.resultKind == .bool) "positive is Bool query"
  expect (pos.body == #[.returnValue (.compare .gt (.stateLoad 0) (.literal 0))])
    "positive returns count > 0"
  let eq ← findMethod plan "equalsCount"
  expect (eq.mode == .mutate && eq.resultKind == .bool) "equalsCount is Bool update"
  expect (eq.body == #[.returnValue (.compare .eq (.stateLoad 0) (.param 0))])
    "equalsCount returns count == delta"
  let files ← liftResult <| filesIcp compiled
  let wat ← findFile files "BoolPredicate.wat"
  let did ← findFile files "BoolPredicate.did"
  expect (wat.contains "i64.gt_u") "unsigned > uses i64.gt_u"
  expect (wat.contains "i64.eq") "equality uses i64.eq"
  expect (wat.contains "(i32.const 126)") "Candid bool opcode 0x7e"
  expect (did.contains "positive : () -> (bool) query;") "did positive bool query"
  expect (did.contains "equalsCount : (nat64) -> (bool);") "did equalsCount bool"
  expect (did.contains "bump : (nat64) -> (nat64);") "did bump stays nat64"
  IO.println "  ✓ BoolPredicate Plan/IR/wat/.did (Candid bool + comparisons)"

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
  let expectPlanFc (programName pathLabel moduleName body needle : String)
      (also : String := "") : IO Unit := do
    let src := wrapProgram programName body
    let compiled ← compileSource session src moduleName pathLabel
    match planFromCompiledSemanticV1 compiled with
    | .error e =>
        expect (e.render.contains needle)
          s!"{programName} Plan FC must contain '{needle}', got: {e.render}"
        unless also.isEmpty do
          expect (e.render.contains also)
            s!"{programName} Plan FC must contain '{also}', got: {e.render}"
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
  expectPlanFc "EcdsaRecoverIcp" "<icp-ecdsa-recover>"
    "Examples.EcdsaRecoverIcp"
    (cryptoBody "pf.crypto.ecdsaRecoverSecp256k1")
    "has no Icp host binding" "ecdsaRecoverSecp256k1"
  IO.println "  ✓ pf.crypto.sha256/keccak256 stay fail closed (no Icp host)"

/-- CAP-1a: `context.unixTimeSeconds` binds `ic0.time` ns÷10⁹ on init,
    update, and query. Residual UInt64 keys stay named fail-closed. -/
private unsafe def testUnixTimeSecondsAdmitted
    (session : Language.Loader.ParserSession) : IO Unit := do
  let src := wrapProgram "UnixTimeIcp" <|
    "  state pad : UInt64\n\n" ++
      "  init() do\n" ++
      "    pad := context.unixTimeSeconds\n\n" ++
      "  entry now() : UInt64 do\n" ++
      "    return context.unixTimeSeconds\n\n" ++
      "  view peek() : UInt64 do\n" ++
      "    return context.unixTimeSeconds\n"
  let compiled ← compileSource session src "Examples.UnixTimeIcp" "<icp-unix-time>"
  let plan ← liftResult <| planIcp compiled
  let initStoresUnix := plan.initializer.body.any fun
    | .store 0 .unixTimeSeconds => true
    | _ => false
  expect initStoresUnix "init must store unixTimeSeconds into pad"
  let now ← findMethod plan "now"
  expect (now.body == #[.returnValue .unixTimeSeconds])
    "entry now must return unixTimeSeconds"
  let peek ← findMethod plan "peek"
  expect (peek.mode == .query) "peek must be a query"
  expect (peek.body == #[.returnValue .unixTimeSeconds])
    "view peek must return unixTimeSeconds"
  let files ← liftResult <| filesIcp compiled
  let wat ← findFile files "UnixTimeIcp.wat"
  expect (wat.contains "\"ic0\" \"time\"") "WAT must import ic0.time"
  expect (wat.contains "(call $ic0_time)") "WAT must call ic0.time"
  expect (wat.contains "i64.div_u") "WAT must divide nanoseconds"
  expect (wat.contains "1000000000") "WAT must use 10^9 seconds divisor"
  expect (wat.contains "(export \"canister_update now\"") "entry export"
  expect (wat.contains "(export \"canister_query peek\"") "query export"
  IO.println "  ✓ context.unixTimeSeconds → ic0.time ns÷10^9 (init/entry/view)"

/-- SYS-S4 residual: ICP has no blockHeight/attachedValue/chainId host.
    Those named UInt64 ContextRead keys stay Plan fail closed. caller/self
    are Principal and stay on the generic ContextRead envelope (ICP-2
    rejects Principal at type closure first). -/
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

/-- Array UInt64 2 flattens to two i64 globals. No Candid vec. -/
private unsafe def testArraySlotsFlatten
    (session : Language.Loader.ParserSession) : IO Unit := do
  let src := wrapProgram "ArrayBox" <|
    "  state slots : Array UInt64 2\n\n" ++
    "  init() do\n" ++
    "    slots[0] := 0\n" ++
    "    slots[1] := 0\n\n" ++
    "  entry set0(v : UInt64) : UInt64 do\n" ++
    "    slots[0] := v\n" ++
    "    return slots[0]\n\n" ++
    "  view get0() : UInt64 do\n" ++
    "    return slots[0]\n"
  let compiled ← compileSource session src "Examples.ArrayBox" "<icp-array-box>"
  let plan ← liftResult <| planIcp compiled
  expect (plan.signedNumeric == false) "ArrayBox stays unsigned"
  expect (plan.states.size == 2) "Array UInt64 2 flattens to two fields"
  expect (plan.states[0]!.name == "slots_0") "leaf slots_0"
  expect (plan.states[1]!.name == "slots_1") "leaf slots_1"
  match validatePlan plan with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"ArrayBox plan must validate: {e.render}"
  let files ← liftResult <| filesIcp compiled
  let wat ← findFile files "ArrayBox.wat"
  let did ← findFile files "ArrayBox.did"
  expect (wat.contains "(global $g_state_0 (mut i64)") "wat global 0"
  expect (wat.contains "(global $g_state_1 (mut i64)") "wat global 1"
  expect (!wat.contains "vec") "no Candid vec in wat"
  expect (!did.contains "vec") "no Candid vec in did"
  expect (did.contains "set0 : (nat64) -> (nat64);") "did set0 stays scalar"
  expect (did.contains "get0 : () -> (nat64) query;") "did get0 stays scalar"
  IO.println "  ✓ Array UInt64 2 flatten (two i64 globals; no Candid vec)"

private unsafe def testBytesBoxFlatten
    (session : Language.Loader.ParserSession) : IO Unit := do
  let src := wrapProgram "BytesBox" <|
    "  state b : Bytes 4\n\n" ++
    "  init() do\n" ++
    "    b[0] := 0\n\n" ++
    "  entry set0(v : UInt64) : UInt64 do\n" ++
    "    b[0] := 0\n" ++
    "    return v\n"
  let compiled ← compileSource session src "Examples.BytesBox" "<icp-bytes-box>"
  let plan ← liftResult <| planIcp compiled
  expect (plan.signedNumeric == false) "BytesBox stays unsigned"
  expect (plan.states.size == 4) "Bytes 4 flattens to four i64 globals"
  expect (plan.states[0]!.name == "b_0") "leaf b_0"
  expect (plan.states[3]!.name == "b_3") "leaf b_3"
  match validatePlan plan with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"BytesBox plan must validate: {e.render}"
  let files ← liftResult <| filesIcp compiled
  let wat ← findFile files "BytesBox.wat"
  let did ← findFile files "BytesBox.did"
  expect (wat.contains "(global $g_state_0 (mut i64)") "wat global 0"
  expect (wat.contains "(global $g_state_3 (mut i64)") "wat global 3"
  expect (!wat.contains "vec") "no Candid vec nat8 in wat"
  expect (!did.contains "vec") "no Candid vec nat8 in did"
  IO.println "  ✓ Bytes 4 flatten (four i64 globals; no Candid vec)"

private unsafe def testArrayN9FailClosed
    (session : Language.Loader.ParserSession) : IO Unit := do
  let src := wrapProgram "ArrN9" <|
    "  state slots : Array UInt64 9\n\n" ++
    "  init() do\n" ++
    "    slots[0] := 0\n\n" ++
    "  entry set0(v : UInt64) : UInt64 do\n" ++
    "    slots[0] := v\n" ++
    "    return v\n"
  let compiled ← compileSource session src "Examples.ArrN9" "<icp-arr-n9>"
  expectPlanErrorContaining "Array N=9" "1..8"
    (planFromCompiledSemanticV1 compiled)
  IO.println "  ✓ Array UInt64 N=9 fail closed"

private unsafe def testArrayElementFailClosed
    (session : Language.Loader.ParserSession) : IO Unit := do
  let src := wrapProgram "ArrInt" <|
    "  state slots : Array Int64 2\n\n" ++
    "  init() do\n" ++
    "    slots[0] := 0\n" ++
    "    slots[1] := 0\n\n" ++
    "  entry set0(v : UInt64) : UInt64 do\n" ++
    "    slots[0] := 0\n" ++
    "    return v\n"
  let compiled ← compileSource session src "Examples.ArrInt" "<icp-arr-int>"
  expectPlanErrorContaining "Array Int64 element" "Array element must be UInt64"
    (planFromCompiledSemanticV1 compiled)
  IO.println "  ✓ Array Int64 element fail closed"

private unsafe def testArrayReturnFailClosed
    (session : Language.Loader.ParserSession) : IO Unit := do
  let src := wrapProgram "ArrRet" <|
    "  state slots : Array UInt64 2\n\n" ++
    "  init() do\n" ++
    "    slots[0] := 0\n" ++
    "    slots[1] := 0\n\n" ++
    "  entry peek() : Array UInt64 2 do\n" ++
    "    return slots\n"
  let compiled ← compileSource session src "Examples.ArrRet" "<icp-arr-ret>"
  expectPlanErrorContaining "Array return" "Array return is outside ICP-2"
    (planFromCompiledSemanticV1 compiled)
  IO.println "  ✓ Array return fail closed"

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

private unsafe def testArrInt64Flatten
    (session : Language.Loader.ParserSession) : IO Unit := do
  let src := wrapProgram "ArrInt64" <|
    "  state slots : Array Int64 2\n\n" ++
    "  init() do\n" ++
    "    slots[0] := 0\n" ++
    "    slots[1] := 0\n\n" ++
    "  entry set0(v : Int64) : Int64 do\n" ++
    "    slots[0] := v\n" ++
    "    return slots[0]\n\n" ++
    "  view get0() : Int64 do\n" ++
    "    return slots[0]\n"
  let compiled ← compileSource session src "Examples.ArrInt64" "<icp-arr-int64>"
  let plan ← liftResult <| planIcp compiled
  expect plan.signedNumeric "ArrInt64 Plan is signed"
  expect (plan.states.size == 2) "Array Int64 2 flattens to two fields"
  expect (plan.states[0]!.name == "slots_0") "leaf slots_0"
  expect (plan.states[1]!.name == "slots_1") "leaf slots_1"
  match validatePlan plan with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"ArrInt64 plan must validate: {e.render}"
  let files ← liftResult <| filesIcp compiled
  let wat ← findFile files "ArrInt64.wat"
  let did ← findFile files "ArrInt64.did"
  expect (wat.contains "(global $g_state_0 (mut i64)") "wat global 0"
  expect (wat.contains "(global $g_state_1 (mut i64)") "wat global 1"
  expect (!wat.contains "vec") "no Candid vec in wat"
  expect (!did.contains "vec") "no Candid vec in did"
  expect (did.contains "set0 : (int64) -> (int64);") "did set0 is int64"
  IO.println "  ✓ Array Int64 2 flatten (two i64 globals; Candid int64; no vec)"

private unsafe def testArrayInt64N9FailClosed
    (session : Language.Loader.ParserSession) : IO Unit := do
  let src := wrapProgram "ArrInt64N9" <|
    "  state slots : Array Int64 9\n\n" ++
    "  init() do\n" ++
    "    slots[0] := 0\n\n" ++
    "  entry set0(v : Int64) : Int64 do\n" ++
    "    slots[0] := v\n" ++
    "    return v\n"
  let compiled ← compileSource session src "Examples.ArrInt64N9" "<icp-arr-int64-n9>"
  expectPlanErrorContaining "Array Int64 N=9" "1..8"
    (planFromCompiledSemanticV1 compiled)
  IO.println "  ✓ Array Int64 N=9 fail closed"

private unsafe def testArrayInt64ReturnFailClosed
    (session : Language.Loader.ParserSession) : IO Unit := do
  let src := wrapProgram "ArrInt64Ret" <|
    "  state slots : Array Int64 2\n\n" ++
    "  init() do\n" ++
    "    slots[0] := 0\n" ++
    "    slots[1] := 0\n\n" ++
    "  entry peek(v : Int64) : Array Int64 2 do\n" ++
    "    return slots\n"
  let compiled ← compileSource session src "Examples.ArrInt64Ret" "<icp-arr-int64-ret>"
  expectPlanErrorContaining "Array Int64 return" "Array return is outside ICP-2"
    (planFromCompiledSemanticV1 compiled)
  IO.println "  ✓ Array Int64 return fail closed"

private unsafe def testPrincipalIdentityLeaves
    (session : Language.Loader.ParserSession) : IO Unit := do
  let src := wrapProgram "PrincipalMix" <|
    "  state owner : Principal\n\n" ++
    "  init(initial : Principal) do\n" ++
    "    owner := initial\n\n" ++
    "  entry set(who : Principal) : Bool do\n" ++
    "    owner := who\n" ++
    "    return true\n\n" ++
    "  entry eq(a : Principal, b : Principal) : Bool do\n" ++
    "    return a == b\n\n" ++
    "  entry matchesOwner(who : Principal) : Bool do\n" ++
    "    return owner == who\n"
  let compiled ← compileSource session src "Examples.PrincipalMix" "<icp-principal>"
  let plan ← liftResult <| planFromCompiledSemanticV1 compiled
  expect (plan.signedNumeric == false) "PrincipalMix stays unsigned"
  expect (plan.states.size == 9) "Principal flattens to nine i64 globals"
  expect (plan.states[0]!.name == "owner_len") "leaf owner_len"
  expect (plan.states[8]!.name == "owner_w7") "leaf owner_w7"
  match validatePlan plan with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"PrincipalMix plan must validate: {e.render}"
  let files ← liftResult <| buildFromCompiledSemanticV1 compiled
  let wat ← findFile files "PrincipalMix.wat"
  let did ← findFile files "PrincipalMix.did"
  expect (wat.contains "(global $g_state_0 (mut i64)") "wat global 0"
  expect (wat.contains "(global $g_state_8 (mut i64)") "wat global 8"
  expect (!wat.contains "principal") "no Candid principal in wat"
  expect (!did.contains "principal") "no Candid principal in did"
  let retSrc := wrapProgram "PrincipalReturn" <|
    "  state owner : Principal\n\n" ++
    "  init(initial : Principal) do\n" ++
    "    owner := initial\n\n" ++
    "  view getOwner() : Principal do\n" ++
    "    return owner\n"
  let compiledRet ← compileSource session retSrc
    "Examples.PrincipalReturn" "<icp-principal-ret>"
  expectPlanErrorContaining "PrincipalReturn" "Principal"
    (planFromCompiledSemanticV1 compiledRet)
  IO.println "  ✓ Principal 9-leaf identity (nine i64 globals; no Candid principal)"

unsafe def run : IO Unit := do
  IO.println "IcpPlanV1"
  let session ← Tests.Language.ParserSession.shared
  testStateCellPlan session
  testStateCellIRAndWat session
  testInt64StateCell session
  testMulDivModAdmit session
  testSignedMulAdmit session
  testBitNotFc session
  testMixedInt64UInt64Fc session
  testBoolPredicate session
  testCallSyncFc session
  testCryptoSha256StayFailClosed session
  testUnixTimeSecondsAdmitted session
  testContextReadStayFailClosed session
  testEnvReadNativeStayFailClosed session
  testEmitFc session
  testInvariantFc session
  testScheduleFc session
  testAggregateFc session
  testArraySlotsFlatten session
  testBytesBoxFlatten session
  testArrInt64Flatten session
  testArrayN9FailClosed session
  testArrayInt64N9FailClosed session
  testArrayElementFailClosed session
  testArrayReturnFailClosed session
  testArrayInt64ReturnFailClosed session
  testRegistryDispatch session
  testCapabilityProductPath session
  testUnknownProfileFailClosed
  testPrincipalIdentityLeaves session
  IO.println "IcpPlanV1: all checks passed"

end Tests.Materialization.IcpPlanV1
