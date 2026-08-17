/-
  ICP Plan/IR/WAT engineering suite (ICP-2 Counter/StateCell leaf, ADR-0047).

  Pins StateCell plan shape (public UInt64 **or** homogeneous Int64 state,
  init/entry(mutate)/view, checked add/sub/mul/div/mod), IR/wat/.did surface (ic0 imports,
  mutable i64 state globals, DIDL/LEB128 header handling,
  canister_init/canister_update/canister_query exports, Candid nat64 or
  int64 service), registry materialize dispatch, and explicit fail-closed
  boundaries (sync call, emit, schedule, nonempty invariant,
  aggregates/mixed UInt64+Int64; Array UInt64 N∈1..8 flatten is admitted;
  Map UInt64 UInt64 cap-8 flattens to 24 i64 globals, no Candid map).
  CAP-1a admits `context.unixTimeSeconds` as
  `ic0.time` ns÷10⁹ on init/update/query; other UInt64 ContextRead keys stay
  named fail-closed. CAP-1b admits `context.caller` as ADR-0025-class
  Principal (`u32le(len)‖bytes`) via `ic0.msg_caller_size` /
  `ic0.msg_caller_copy` on init/entry only; query/view stays named
  `ICP-VIEW-CALLER` fail-closed (S1 consistency with NEAR/CosmWasm).

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
  expect (!wat.contains "msg_caller_size")
    "StateCell must not import ic0.msg_caller_size (caller is use-gated)"
  expect (!wat.contains "msg_caller_copy")
    "StateCell must not import ic0.msg_caller_copy (caller is use-gated)"
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

/-- CAP-1b: `context.caller` binds `ic0.msg_caller_size` /
    `ic0.msg_caller_copy` on init/entry. Principal wire is ADR-0025-class
    `u32le(len)‖bytes` (max 29). Query/view stays named fail-closed. -/
private unsafe def testCallerAdmitted
    (session : Language.Loader.ParserSession) : IO Unit := do
  let src := wrapProgram "CallerIcp" <|
    "  state owner : Principal\n" ++
      "  state pad : UInt64\n\n" ++
      "  init() do\n" ++
      "    owner := context.caller\n" ++
      "    pad := 0\n\n" ++
      "  entry who(a : Principal) : Bool do\n" ++
      "    return context.caller == a\n\n" ++
      "  view peek() : UInt64 do\n" ++
      "    return pad\n"
  let compiled ← compileSource session src "Examples.CallerIcp" "<icp-caller>"
  let plan ← liftResult <| planIcp compiled
  expect (plan.states.size == 10)
    s!"owner Principal must flatten to 9 leaves + pad, got {plan.states.size}"
  expect (plan.states[0]!.name == "owner_len") "first Principal leaf is owner_len"
  expect (plan.states[9]!.name == "pad") "UInt64 pad stays a scalar leaf"
  let initStoresCaller := plan.initializer.body.any fun
    | .store 0 .callerPrincipalLen => true
    | _ => false
  expect initStoresCaller "init must store callerPrincipalLen into owner_len"
  let who ← findMethod plan "who"
  expect (who.mode == .mutate) "who must be an update"
  expect (who.resultKind == .bool) "who must return Bool"
  expect (who.paramKinds == #[.principal]) "who param is Principal"
  let whoReturnsPrincipalEq :=
    match who.body.back? with
    | some (.returnValue (.principalEq lhs rhs)) =>
        lhs.size == 9 && rhs.size == 9
    | _ => false
  expect whoReturnsPrincipalEq "entry who must return principalEq of 9+9 leaves"
  let files ← liftResult <| filesIcp compiled
  let wat ← findFile files "CallerIcp.wat"
  expect (wat.contains "\"ic0\" \"msg_caller_size\"")
    "WAT must import ic0.msg_caller_size"
  expect (wat.contains "\"ic0\" \"msg_caller_copy\"")
    "WAT must import ic0.msg_caller_copy"
  expect (wat.contains "(call $ic0_msg_caller_size)")
    "WAT must call ic0.msg_caller_size"
  expect (wat.contains "(call $ic0_msg_caller_copy")
    "WAT must call ic0.msg_caller_copy"
  expect (wat.contains "u32le(len)")
    "WAT must name ADR-0025-class u32le(len)||bytes framing"
  expect (wat.contains "(export \"canister_update who\"") "entry export"
  expect (wat.contains "(export \"canister_query peek\"") "query export"
  let did ← findFile files "CallerIcp.did"
  expect (did.contains "who : (principal) -> (bool);")
    s!"did who must take principal, got: {did}"
  -- Usage-gated: StateCell-shaped program without caller is checked above.
  -- Locked wat2wasm must still accept the caller WAT.
  let selection ← liftResult <| resolveBuildSelectionV1 TargetId.icp none
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
      "CallerIcp locked wat2wasm finalization must be deployable"
    expect (FinalizedArtifactsV1.extraFilesOf finalized == #["CallerIcp.wasm"])
      "CallerIcp Finalize must add exactly CallerIcp.wasm"
  IO.println "  ✓ context.caller → ic0.msg_caller_* (init/entry; ADR-0025 framing)"

/-- CAP-1b ICP-VIEW-CALLER: query/view keeps context.caller fail-closed
    (S1 consistency with NEAR predecessor / CosmWasm MessageInfo.sender).
    ic0.msg_caller is available on queries; this profile still refuses it. -/
private unsafe def testCallerViewFailClosed
    (session : Language.Loader.ParserSession) : IO Unit := do
  let src := wrapProgram "CallerViewIcp" <|
    "  state pad : UInt64\n\n" ++
      "  init() do\n" ++
      "    pad := 0\n\n" ++
      "  entry bump() : UInt64 do\n" ++
      "    pad := pad + 1\n" ++
      "    return pad\n\n" ++
      "  view who() : Bool do\n" ++
      "    let c : Principal := context.caller\n" ++
      "    return c == c\n"
  let compiled ← compileSource session src "Examples.CallerViewIcp"
    "<icp-caller-view>"
  match planFromCompiledSemanticV1 compiled with
  | .error e =>
      expect (e.render.contains "ICP-VIEW-CALLER")
        s!"view caller FC must name ICP-VIEW-CALLER, got: {e.render}"
      expect (e.render.contains "query/view" || e.render.contains "view")
        s!"view caller FC must cite query/view, got: {e.render}"
  | .ok _ =>
      throw <| IO.userError
        "CallerViewIcp must Plan fail closed (CAP-1b ICP-VIEW-CALLER)"
  IO.println "  ✓ context.caller query/view named FC (ICP-VIEW-CALLER)"

/-- SYS-S4 residual: ICP has no blockHeight/attachedValue/chainId host.
    Those named UInt64 ContextRead keys stay Plan fail closed. context.self
    stays on the generic ContextRead envelope. -/
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

/-- PointBox: named Struct flattens to two extra i64 globals. No Candid record. -/
private unsafe def testPointBoxFlatten
    (session : Language.Loader.ParserSession) : IO Unit := do
  let src := wrapProgram "PointBox" <|
    "  struct Point where\n" ++
    "    x : UInt64\n" ++
    "    y : UInt64\n" ++
    "  state p : Point\n\n" ++
    "  init() do\n" ++
    "    p := Point.new(0, 0)\n\n" ++
    "  entry setX(v : UInt64) : UInt64 do\n" ++
    "    p.x := v\n" ++
    "    return p.x\n\n" ++
    "  view getX() : UInt64 do\n" ++
    "    return p.x\n"
  let compiled ← compileSource session src "Examples.PointBox" "<icp-point-box>"
  let plan ← liftResult <| planIcp compiled
  expect (plan.states.map (·.name) == #["p_x", "p_y"])
    "PointBox must flatten to p_x/p_y"
  match validatePlan plan with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"PointBox plan must validate: {e.render}"
  let files ← liftResult <| filesIcp compiled
  expect (!files.isEmpty) "PointBox must materialize files"
  let wat ← findFile files "PointBox.wat"
  let did ← findFile files "PointBox.did"
  expect (wat.contains "(global $g_state_0 (mut i64)") "wat global 0"
  expect (wat.contains "(global $g_state_1 (mut i64)") "wat global 1"
  expect (!wat.contains "record") "no Candid record in wat"
  expect (!did.contains "record") "no Candid record in did"
  expect (!wat.contains "variant") "no Candid variant in wat"
  expect (!did.contains "variant") "no Candid variant in did"
  IO.println "  ✓ PointBox named Struct flatten (two i64 globals; no Candid record)"
  -- Named Struct/Enum returns are covered by T6 view/entry aggregate pins below
  -- (`testPointViewRet` / `testPairRetEntry`); do not pin a stale entry-FC here.

/-- MaybeMark: named Enum flattens to tag+payload i64 globals. No Candid variant. -/
private unsafe def testMaybeMarkFlatten
    (session : Language.Loader.ParserSession) : IO Unit := do
  let src := wrapProgram "MaybeMark" <|
    "  enum Maybe where\n" ++
    "    | None\n" ++
    "    | Some(UInt64)\n" ++
    "  state m : Maybe\n\n" ++
    "  init() do\n" ++
    "    m := Maybe.None()\n\n" ++
    "  entry put(v : UInt64) : UInt64 do\n" ++
    "    m := Maybe.Some(v)\n" ++
    "    return v\n"
  let compiled ← compileSource session src "Examples.MaybeMark" "<icp-maybe-mark>"
  let plan ← liftResult <| planIcp compiled
  expect (plan.states.map (·.name) == #["m_tag", "m_p0"])
    "MaybeMark must flatten to m_tag/m_p0"
  match validatePlan plan with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"MaybeMark plan must validate: {e.render}"
  let files ← liftResult <| filesIcp compiled
  expect (!files.isEmpty) "MaybeMark must materialize files"
  let wat ← findFile files "MaybeMark.wat"
  let did ← findFile files "MaybeMark.did"
  expect (wat.contains "(global $g_state_0 (mut i64)") "wat global 0"
  expect (wat.contains "(global $g_state_1 (mut i64)") "wat global 1"
  expect (!wat.contains "record") "no Candid record in wat"
  expect (!did.contains "record") "no Candid record in did"
  expect (!wat.contains "variant") "no Candid variant in wat"
  expect (!did.contains "variant") "no Candid variant in did"
  IO.println "  ✓ MaybeMark named Enum flatten (two i64 globals; no Candid variant)"

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

/-- Option UInt64 flattens to two i64 globals. No Candid `opt`. -/
private unsafe def testOptBoxFlatten
    (session : Language.Loader.ParserSession) : IO Unit := do
  let src := wrapProgram "OptBox" <|
    "  state o : Option UInt64\n\n" ++
    "  init() do\n" ++
    "    o := Option.none()\n\n" ++
    "  entry setSome(v : UInt64) : UInt64 do\n" ++
    "    o := Option.some(v)\n" ++
    "    return v\n"
  let compiled ← compileSource session src "Examples.OptBox" "<icp-opt-box>"
  let plan ← liftResult <| planFromCompiledSemanticV1 compiled
  expect (plan.signedNumeric == false) "OptBox stays unsigned"
  expect (plan.states.size == 2) "Option UInt64 flattens to two i64 globals"
  expect (plan.states[0]!.name == "o_tag") "leaf o_tag"
  expect (plan.states[1]!.name == "o_p0") "leaf o_p0"
  expect (plan.initializer.body.size == 2) "init stores both Option leaves"
  let some setSome := plan.entries[0]? |
    throw <| IO.userError "missing setSome entry"
  expect (setSome.body.size == 3)
    "setSome stores both Option leaves then returns"
  match validatePlan plan with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"OptBox plan must validate: {e.render}"
  let files ← liftResult <| buildFromCompiledSemanticV1 compiled
  let wat ← findFile files "OptBox.wat"
  let did ← findFile files "OptBox.did"
  expect (wat.contains "(global $g_state_0 (mut i64)") "wat global 0"
  expect (wat.contains "(global $g_state_1 (mut i64)") "wat global 1"
  expect (!wat.contains "(opt") "no Candid opt type in wat"
  expect (!did.contains "opt") "no Candid opt in did"
  IO.println "  ✓ Option UInt64 flatten (two i64 globals; no Candid opt)"

unsafe def testOptRetBox
    (session : Language.Loader.ParserSession) : IO Unit := do
  let src := wrapProgram "OptRetBox" <|
    "  state o : Option UInt64\n\n" ++
    "  init() do\n" ++
    "    o := Option.none()\n\n" ++
    "  entry peek() : Option UInt64 do\n" ++
    "    return o\n"
  let compiled ← compileSource session src "Examples.OptRetBox" "<icp-opt-ret>"
  let plan ← liftResult <| planFromCompiledSemanticV1 compiled
  let some e := plan.entries[0]? |
    throw <| IO.userError "OptRetBox must emit an entry"
  expect (e.resultKind == .aggregate 2)
    s!"OptRetBox entry must be aggregate 2, got {repr e.resultKind}"
  match validatePlan plan with
  | .ok () => pure ()
  | .error err => throw <| IO.userError s!"OptRetBox plan must validate: {err.render}"
  let files ← liftResult <| buildFromCompiledSemanticV1 compiled
  expect (!files.isEmpty) "OptRetBox must emit nonempty files"
  let did ← findFile files "OptRetBox.did"
  expect (did.contains "-> (nat64, nat64);")
    s!"OptRetBox .did must be a positional nat64 tuple update, got:\n{did}"
  expect (!did.contains "query") "OptRetBox entry must not be a Candid query"
  expect (!did.contains "opt") "OptRetBox .did must not emit Candid opt"
  IO.println "  ✓ OptRetBox entry Candid positional tuple"

private unsafe def testOptionInt64PayloadFailClosed
    (session : Language.Loader.ParserSession) : IO Unit := do
  let src := wrapProgram "OptInt" <|
    "  state o : Option Int64\n\n" ++
    "  init() do\n" ++
    "    o := Option.none()\n\n" ++
    "  entry setSome(v : UInt64) : UInt64 do\n" ++
    "    o := Option.some(0)\n" ++
    "    return v\n"
  let compiled ← compileSource session src "Examples.OptInt" "<icp-opt-int>"
  expectPlanErrorContaining "Option Int64" "requires UInt64 payload"
    (planFromCompiledSemanticV1 compiled)
  IO.println "  ✓ Option Int64 payload fail closed"

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

unsafe def testArrRetBox
    (session : Language.Loader.ParserSession) : IO Unit := do
  let src := wrapProgram "ArrRetBox" <|
    "  state slots : Array UInt64 2\n\n" ++
    "  init() do\n" ++
    "    slots[0] := 0\n" ++
    "    slots[1] := 0\n\n" ++
    "  entry peek() : Array UInt64 2 do\n" ++
    "    return slots\n"
  let compiled ← compileSource session src "Examples.ArrRetBox" "<icp-arr-ret>"
  let plan ← liftResult <| planFromCompiledSemanticV1 compiled
  let some e := plan.entries[0]? |
    throw <| IO.userError "ArrRetBox must emit an entry"
  expect (e.resultKind == .aggregate 2)
    s!"ArrRetBox entry must be aggregate 2, got {repr e.resultKind}"
  match validatePlan plan with
  | .ok () => pure ()
  | .error err => throw <| IO.userError s!"ArrRetBox plan must validate: {err.render}"
  let files ← liftResult <| buildFromCompiledSemanticV1 compiled
  expect (!files.isEmpty) "ArrRetBox must emit nonempty files"
  let did ← findFile files "ArrRetBox.did"
  let wat ← findFile files "ArrRetBox.wat"
  expect (did.contains "-> (nat64, nat64);")
    s!"ArrRetBox .did must be a positional nat64 tuple update, got:\n{did}"
  expect (!did.contains "query") "ArrRetBox entry must not be a Candid query"
  expect (!wat.contains "record") "ArrRetBox wat must not emit Candid record"
  expect (!did.contains "record") "ArrRetBox .did must not emit Candid record"
  expect (!did.contains "vec") "ArrRetBox .did must not emit Candid vec"
  IO.println "  ✓ ArrRetBox entry Candid positional tuple"

unsafe def testMaybeRetBox
    (session : Language.Loader.ParserSession) : IO Unit := do
  let src := wrapProgram "MaybeRetBox" <|
    "  enum Maybe where\n" ++
    "    | None\n" ++
    "    | Some(UInt64)\n" ++
    "  state m : Maybe\n\n" ++
    "  init() do\n" ++
    "    m := Maybe.None()\n\n" ++
    "  entry peek() : Maybe do\n" ++
    "    return m\n"
  let compiled ← compileSource session src "Examples.MaybeRetBox" "<icp-maybe-ret>"
  let plan ← liftResult <| planFromCompiledSemanticV1 compiled
  let some e := plan.entries[0]? |
    throw <| IO.userError "MaybeRetBox must emit an entry"
  expect (e.resultKind == .aggregate 2)
    s!"MaybeRetBox entry must be aggregate 2, got {repr e.resultKind}"
  match validatePlan plan with
  | .ok () => pure ()
  | .error err => throw <| IO.userError s!"MaybeRetBox plan must validate: {err.render}"
  let files ← liftResult <| buildFromCompiledSemanticV1 compiled
  expect (!files.isEmpty) "MaybeRetBox must emit nonempty files"
  IO.println "  ✓ MaybeRetBox entry Candid positional tuple"

unsafe def testPairRetEntry
    (session : Language.Loader.ParserSession) : IO Unit := do
  let src := wrapProgram "PairRetEntry" <|
    "  struct Pair where\n" ++
    "    a : UInt64\n" ++
    "    b : UInt64\n" ++
    "  state unused : UInt64\n\n" ++
    "  init() do\n" ++
    "    unused := 0\n\n" ++
    "  entry makePair(x : UInt64, y : UInt64) : Pair do\n" ++
    "    return Pair.new(x, y)\n"
  let compiled ← compileSource session src "Examples.PairRetEntry" "<icp-pair-ret-entry>"
  let plan ← liftResult <| planFromCompiledSemanticV1 compiled
  let some e := plan.entries[0]? |
    throw <| IO.userError "PairRetEntry must emit an entry"
  expect (e.resultKind == .aggregate 2)
    s!"PairRetEntry entry must be aggregate 2, got {repr e.resultKind}"
  match validatePlan plan with
  | .ok () => pure ()
  | .error err => throw <| IO.userError s!"PairRetEntry plan must validate: {err.render}"
  let files ← liftResult <| buildFromCompiledSemanticV1 compiled
  expect (!files.isEmpty) "PairRetEntry must emit nonempty files"
  IO.println "  ✓ PairRetEntry entry Candid positional tuple"

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
  expectPlanErrorContaining "Array Int64 return" "element must be UInt64"
    (planFromCompiledSemanticV1 compiled)
  IO.println "  ✓ Array Int64 return fail closed"

/-- T6: view-only Array UInt64 N return as Candid positional tuple. Entry stays FC. -/
unsafe def testArrViewRet
    (session : Language.Loader.ParserSession) : IO Unit := do
  let src := wrapProgram "ArrViewRet" <|
    "  state slots : Array UInt64 2\n\n" ++
    "  init() do\n" ++
    "    slots[0] := 0\n" ++
    "    slots[1] := 0\n\n" ++
    "  view peek() : Array UInt64 2 do\n" ++
    "    return slots\n"
  let compiled ← compileSource session src "Examples.ArrViewRet" "<icp-arr-view-ret>"
  let plan ← liftResult <| planIcp compiled
  let some v := plan.views[0]? |
    throw <| IO.userError "ArrViewRet must emit a view"
  expect (v.resultKind == .aggregate 2)
    s!"ArrViewRet view must be aggregate 2, got {repr v.resultKind}"
  match validatePlan plan with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"ArrViewRet plan must validate: {e.render}"
  let files ← liftResult <| filesIcp compiled
  expect (!files.isEmpty) "ArrViewRet must emit nonempty files"
  let did ← findFile files "ArrViewRet.did"
  let wat ← findFile files "ArrViewRet.wat"
  expect (did.contains "-> (nat64, nat64) query")
    s!"ArrViewRet .did must be a positional nat64 tuple query, got:\n{did}"
  expect (!wat.contains "(opt") "ArrViewRet wat must not emit Candid opt"
  expect (!wat.contains "record") "ArrViewRet wat must not emit Candid record"
  expect (!wat.contains "variant") "ArrViewRet wat must not emit Candid variant"
  expect (!wat.contains "vec") "ArrViewRet wat must not emit Candid vec"
  expect (!did.contains "record") "ArrViewRet .did must not emit Candid record"
  expect (!did.contains "opt") "ArrViewRet .did must not emit Candid opt"
  expect (!did.contains "vec") "ArrViewRet .did must not emit Candid vec"
  expect (!did.contains "variant") "ArrViewRet .did must not emit Candid variant"
  IO.println "  ✓ ArrViewRet view-only Candid positional tuple"

/-- T8b: view-only Bytes 4 return as Candid positional 4-tuple. Entry stays FC. -/
unsafe def testBytesViewRet
    (session : Language.Loader.ParserSession) : IO Unit := do
  let src := wrapProgram "BytesRetBox" <|
    "  state b : Bytes 4\n\n" ++
    "  init() do\n" ++
    "    b[0] := 0\n\n" ++
    "  view get() : Bytes 4 do\n" ++
    "    return b\n"
  let compiled ← compileSource session src "Examples.BytesRetBox" "<icp-bytes-view-ret>"
  let plan ← liftResult <| planIcp compiled
  let some v := plan.views[0]? |
    throw <| IO.userError "BytesRetBox must emit a view"
  expect (v.resultKind == .aggregate 4)
    s!"BytesRetBox view must be aggregate 4, got {repr v.resultKind}"
  match validatePlan plan with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"BytesRetBox plan must validate: {e.render}"
  let files ← liftResult <| filesIcp compiled
  let did ← findFile files "BytesRetBox.did"
  let wat ← findFile files "BytesRetBox.wat"
  expect (did.contains "-> (nat64, nat64, nat64, nat64) query")
    s!"BytesRetBox .did must be a positional 4-nat64 query, got:\n{did}"
  expect (!did.contains "vec") "BytesRetBox .did must not emit Candid vec"
  expect (!wat.contains "vec") "BytesRetBox wat must not emit Candid vec"
  let entrySrc := wrapProgram "BytesRetEntry" <|
    "  state b : Bytes 4\n\n" ++
    "  init() do\n" ++
    "    b[0] := 0\n\n" ++
    "  entry peek() : Bytes 4 do\n" ++
    "    return b\n"
  let compiledEntry ← compileSource session entrySrc
    "Examples.BytesRetEntry" "<icp-bytes-entry-ret>"
  expectPlanErrorContaining "BytesRetEntry" "Bytes return"
    (planIcp compiledEntry)
  IO.println "  ✓ BytesRetBox view-only Candid positional 4-tuple"

/-- T6: view-only Option UInt64 return as Candid positional tuple. Entry stays FC. -/
unsafe def testOptViewRet
    (session : Language.Loader.ParserSession) : IO Unit := do
  let src := wrapProgram "OptViewRet" <|
    "  state o : Option UInt64\n\n" ++
    "  init() do\n" ++
    "    o := Option.none()\n\n" ++
    "  view peek() : Option UInt64 do\n" ++
    "    return o\n"
  let compiled ← compileSource session src "Examples.OptViewRet" "<icp-opt-view-ret>"
  let plan ← liftResult <| planIcp compiled
  let some v := plan.views[0]? |
    throw <| IO.userError "OptViewRet must emit a view"
  expect (v.resultKind == .aggregate 2)
    s!"OptViewRet view must be aggregate 2, got {repr v.resultKind}"
  match validatePlan plan with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"OptViewRet plan must validate: {e.render}"
  let files ← liftResult <| filesIcp compiled
  expect (!files.isEmpty) "OptViewRet must emit nonempty files"
  let did ← findFile files "OptViewRet.did"
  expect (did.contains "-> (nat64, nat64) query")
    s!"OptViewRet .did must be a positional nat64 tuple query, got:\n{did}"
  expect (!did.contains "opt") "OptViewRet .did must not emit Candid opt"
  IO.println "  ✓ OptViewRet view-only Candid positional tuple"

/-- T6: view-only named Struct return as Candid positional tuple. Entry stays FC. -/
unsafe def testPointViewRet
    (session : Language.Loader.ParserSession) : IO Unit := do
  let src := wrapProgram "PointViewRet" <|
    "  struct Point where\n" ++
    "    x : UInt64\n" ++
    "    y : UInt64\n" ++
    "  state p : Point\n\n" ++
    "  init() do\n" ++
    "    p := Point.new(0, 0)\n\n" ++
    "  view getPoint() : Point do\n" ++
    "    return p\n"
  let compiled ← compileSource session src "Examples.PointViewRet" "<icp-point-view-ret>"
  let plan ← liftResult <| planIcp compiled
  let some v := plan.views[0]? |
    throw <| IO.userError "PointViewRet must emit a view"
  expect (v.resultKind == .aggregate 2)
    s!"PointViewRet view must be aggregate 2, got {repr v.resultKind}"
  match validatePlan plan with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"PointViewRet plan must validate: {e.render}"
  let files ← liftResult <| filesIcp compiled
  expect (!files.isEmpty) "PointViewRet must emit nonempty files"
  let did ← findFile files "PointViewRet.did"
  let wat ← findFile files "PointViewRet.wat"
  expect (did.contains "-> (nat64, nat64) query")
    s!"PointViewRet .did must be a positional nat64 tuple query, got:\n{did}"
  expect (!did.contains "record") "PointViewRet .did must not emit Candid record"
  expect (!wat.contains "record") "PointViewRet wat must not emit Candid record"
  IO.println "  ✓ PointViewRet view-only Candid positional tuple"

/-- T6: view-only named Enum return as Candid positional tuple. Entry stays FC. -/
unsafe def testMaybeViewRet
    (session : Language.Loader.ParserSession) : IO Unit := do
  let src := wrapProgram "MaybeViewRet" <|
    "  enum Maybe where\n" ++
    "    | None\n" ++
    "    | Some(UInt64)\n" ++
    "  state m : Maybe\n\n" ++
    "  init() do\n" ++
    "    m := Maybe.None()\n\n" ++
    "  view peek() : Maybe do\n" ++
    "    return m\n"
  let compiled ← compileSource session src "Examples.MaybeViewRet" "<icp-maybe-view-ret>"
  let plan ← liftResult <| planIcp compiled
  let some v := plan.views[0]? |
    throw <| IO.userError "MaybeViewRet must emit a view"
  expect (v.resultKind == .aggregate 2)
    s!"MaybeViewRet view must be aggregate 2, got {repr v.resultKind}"
  match validatePlan plan with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"MaybeViewRet plan must validate: {e.render}"
  let files ← liftResult <| filesIcp compiled
  expect (!files.isEmpty) "MaybeViewRet must emit nonempty files"
  let did ← findFile files "MaybeViewRet.did"
  expect (did.contains "-> (nat64, nat64) query")
    s!"MaybeViewRet .did must be a positional nat64 tuple query, got:\n{did}"
  expect (!did.contains "variant") "MaybeViewRet .did must not emit Candid variant"
  IO.println "  ✓ MaybeViewRet view-only Candid positional tuple"

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
  -- CAP-1b: Principal *params* are Candid `principal` (decode into 9-leaf
  -- identity); state remains nine i64 globals (not a Candid principal cell).
  expect (did.contains "principal")
    "PrincipalMix .did must use Candid principal for Principal params"
  expect (wat.contains "pf_decode_candid_principal")
    "PrincipalMix wat must decode Candid principal params"
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
  IO.println "  ✓ Principal 9-leaf state + Candid principal params (CAP-1b)"

/-- Dense Map UInt64 UInt64 flattens to 24 i64 globals (cap-8 × occ/key/val).
    No Candid `vec`/`record`/`map`. Cap-8 overflow is a Plan assert. -/
private unsafe def testMapMiniFlatten
    (session : Language.Loader.ParserSession) : IO Unit := do
  let src := wrapProgram "MapMini" <|
    "  state m : Map UInt64 UInt64\n\n" ++
    "  init() do\n" ++
    "    m := Map.empty()\n\n" ++
    "  entry put(k : UInt64, v : UInt64) : UInt64 do\n" ++
    "    m[k] := v\n" ++
    "    return v\n"
  let compiled ← compileSource session src "Examples.MapMini" "<icp-map-mini>"
  let plan ← liftResult <| planIcp compiled
  expect (!plan.signedNumeric) "MapMini stays unsigned"
  expect (plan.states.size == 24)
    s!"Map UInt64 cap-8 must flatten to 24 leaves, got {plan.states.size}"
  expect (plan.states[0]!.name == "m_0" && plan.states[23]!.name == "m_23")
    "Map flatten leaf names must be m_0..m_23"
  let initStores := plan.initializer.body.filterMap (fun
    | .store .. => some ()
    | _ => none)
  expect (initStores.size == 24) "MapMini init must store all 24 Map leaves"
  expect (plan.entries.size == 1) "MapMini has one entry"
  let put := plan.entries[0]!
  let putStores := put.body.filterMap (fun
    | .store .. => some ()
    | _ => none)
  let putAsserts := put.body.filterMap (fun
    | .assert .. => some ()
    | _ => none)
  expect (putStores.size == 24) "MapMini put must store all 24 Map leaves"
  expect (putAsserts.size ≥ 1) "MapMini put must check cap-8 overflow"
  match validatePlan plan with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"MapMini plan must validate: {e.render}"
  let files ← liftResult <| filesIcp compiled
  let wat ← findFile files "MapMini.wat"
  let did ← findFile files "MapMini.did"
  expect (wat.contains "(global $g_state_0 (mut i64)") "wat global 0"
  expect (wat.contains "(global $g_state_23 (mut i64)") "wat global 23"
  expect (wat.contains "unreachable") "cap-8 assert must trap"
  expect (!wat.contains "vec") "no Candid vec in wat"
  expect (!wat.contains "record") "no Candid record in wat"
  expect (!did.contains "vec") "no Candid vec in did"
  expect (!did.contains "record") "no Candid record in did"
  expect (!did.contains "map") "no Candid map in did"
  expect (!did.contains "opt") "no Candid opt in did"
  expect (did.contains "put : (nat64, nat64) -> (nat64);") "did put stays scalar"
  IO.println "  ✓ Map UInt64 cap-8 flatten (24 i64 globals; no Candid map/vec)"

/-- Map of Int64 stays fail closed. -/
private unsafe def testMapInt64ElementFc
    (session : Language.Loader.ParserSession) : IO Unit := do
  let src := wrapProgram "MapInt" <|
    "  state m : Map UInt64 Int64\n\n" ++
    "  init() do\n" ++
    "    m := Map.empty()\n\n" ++
    "  entry put(k : UInt64, v : UInt64) : UInt64 do\n" ++
    "    return v\n"
  let compiled ← compileSource session src "Examples.MapInt" "<icp-map-int>"
  expectPlanErrorContaining "MapInt" "Map state admits only Map UInt64 UInt64"
    (planIcp compiled)

/-- Map entry return stays outside ICP-2 (24-tuple would be dishonest). -/
private unsafe def testMapReturnFc
    (session : Language.Loader.ParserSession) : IO Unit := do
  let src := wrapProgram "MapRet" <|
    "  state m : Map UInt64 UInt64\n\n" ++
    "  init() do\n" ++
    "    m := Map.empty()\n\n" ++
    "  entry peek() : Map UInt64 UInt64 do\n" ++
    "    return m\n"
  let compiled ← compileSource session src "Examples.MapRet" "<icp-map-ret>"
  expectPlanErrorContaining "MapRet" "Array/Map return"
    (planIcp compiled)

/-- T9a: if-diamond only. BranchFlow.apply (match/switch) stays fail closed. -/
private unsafe def testIfFlow
    (session : Language.Loader.ParserSession) : IO Unit := do
  let src := wrapProgram "IfFlow" <|
    "  state count : UInt64\n\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n\n" ++
    "  entry bump(delta : UInt64) : UInt64 do\n" ++
    "    if count > 0 then\n" ++
    "      count := count + delta\n" ++
    "    else\n" ++
    "      count := delta\n" ++
    "    return count\n\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let compiled ← compileSource session src "Examples.IfFlow" "<icp-if-flow>"
  let plan ← liftResult <| planIcp compiled
  let bump ← findMethod plan "bump"
  expect (bump.body == #[
      .ifThenElse (.compare .gt (.stateLoad 0) (.literal 0))
        #[.store 0 (.checkedAdd (.stateLoad 0) (.param 0))]
        #[.store 0 (.param 0)],
      .returnValue (.stateLoad 0)])
    "IfFlow bump must lower the branch diamond then join return"
  match validatePlan plan with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"IfFlow plan must validate: {e.render}"
  let files ← liftResult <| filesIcp compiled
  let wat ← findFile files "IfFlow.wat"
  expect (wat.contains "(if (i32.eqz (i64.eqz")
    "IfFlow WAT must render a Wasm if on the Bool condition"
  expect (wat.contains "i64.add")
    "IfFlow WAT must render the then-arm checked add"
  expect (wat.contains "(global.set $g_state_0")
    "IfFlow WAT must store inside the if arms"
  IO.println "  ✓ IfFlow if-diamond"

/-- T9b: integer match (`apply`) plus Option tag match. -/
private unsafe def testBranchFlow
    (session : Language.Loader.ParserSession) : IO Unit := do
  let src := wrapProgram "BranchFlow" <|
    "  state count : UInt64\n\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n\n" ++
    "  entry bump(delta : UInt64) : UInt64 do\n" ++
    "    if count > 0 then\n" ++
    "      count := count + delta\n" ++
    "    else\n" ++
    "      count := delta\n" ++
    "    return count\n\n" ++
    "  entry apply(choice : UInt64) : UInt64 do\n" ++
    "    match choice with\n" ++
    "    | 0 => do\n" ++
    "      return count\n" ++
    "    | 1 => do\n" ++
    "      count := count + 1\n" ++
    "    | other => do\n" ++
    "      count := other\n" ++
    "    return count\n\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let compiled ← compileSource session src "Examples.BranchFlow" "<icp-branch-flow>"
  let plan ← liftResult <| planIcp compiled
  let bump ← findMethod plan "bump"
  expect (bump.body == #[
      .ifThenElse (.compare .gt (.stateLoad 0) (.literal 0))
        #[.store 0 (.checkedAdd (.stateLoad 0) (.param 0))]
        #[.store 0 (.param 0)],
      .returnValue (.stateLoad 0)])
    "BranchFlow bump must keep the T9a if-diamond"
  let apply ← findMethod plan "apply"
  let hasSwitch :=
    apply.body.any fun s =>
      match s with
      | .switchOn _ cases _ =>
          cases.any (fun (v, _) => v == 0) && cases.any (fun (v, _) => v == 1)
      | _ => false
  expect hasSwitch "BranchFlow apply must lower match to switchOn with cases 0 and 1"
  match validatePlan plan with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"BranchFlow plan must validate: {e.render}"
  let files ← liftResult <| filesIcp compiled
  let wat ← findFile files "BranchFlow.wat"
  expect (wat.contains "(if (i32.eqz (i64.eqz")
    "BranchFlow WAT must render Wasm if for bump and/or switch"
  IO.println "  ✓ BranchFlow if + integer match"

private unsafe def testMaybeMatch
    (session : Language.Loader.ParserSession) : IO Unit := do
  let src := wrapProgram "MaybeMatch" <|
    "  state slot : Option UInt64\n\n" ++
    "  init() do\n" ++
    "    slot := Option.none()\n\n" ++
    "  entry take() : UInt64 do\n" ++
    "    match slot with\n" ++
    "    | Option.some(x) => do\n" ++
    "      return x\n" ++
    "    | _ => do\n" ++
    "      return 0\n\n" ++
    "  view peek() : UInt64 do\n" ++
    "    return 0\n"
  let compiled ← compileSource session src "Examples.MaybeMatch" "<icp-maybe-match>"
  let plan ← liftResult <| planIcp compiled
  let take ← findMethod plan "take"
  let hasSwitch :=
    take.body.any fun s =>
      match s with
      | .switchOn _ cases _ =>
          cases.any (fun (v, _) => v == 0) || cases.any (fun (v, _) => v == 1)
      | _ => false
  expect hasSwitch "MaybeMatch take must switch on the Option tag leaf"
  match validatePlan plan with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"MaybeMatch plan must validate: {e.render}"
  IO.println "  ✓ MaybeMatch Option tag switch"

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
  testCallerAdmitted session
  testCallerViewFailClosed session
  testContextReadStayFailClosed session
  testEnvReadNativeStayFailClosed session
  testEmitFc session
  testInvariantFc session
  testScheduleFc session
  testPointBoxFlatten session
  testMaybeMarkFlatten session
  testArraySlotsFlatten session
  testBytesBoxFlatten session
  testOptBoxFlatten session
  testOptRetBox session
  testMaybeRetBox session
  testPairRetEntry session
  testOptionInt64PayloadFailClosed session
  testArrInt64Flatten session
  testArrayN9FailClosed session
  testArrayInt64N9FailClosed session
  testArrayElementFailClosed session
  testArrRetBox session
  testArrayInt64ReturnFailClosed session
  testArrViewRet session
  testBytesViewRet session
  testOptViewRet session
  testPointViewRet session
  testMaybeViewRet session
  testRegistryDispatch session
  testCapabilityProductPath session
  testUnknownProfileFailClosed
  testPrincipalIdentityLeaves session
  testMapMiniFlatten session
  testMapInt64ElementFc session
  testMapReturnFc session
  testIfFlow session
  testBranchFlow session
  testMaybeMatch session
  IO.println "IcpPlanV1: all checks passed"

end Tests.Materialization.IcpPlanV1
