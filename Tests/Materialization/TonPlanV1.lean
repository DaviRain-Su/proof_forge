/-
  Ton Plan/IR/Tolk engineering suite (TON-2 StateCell leaf + BL-1 schedule +
  BL-10 named aggregate view returns + BL-23 anonymous Array/Option view
  returns + BL-34 / B-OPT-STATE Option UInt64 state + BL-38 / B-CTX-OPEN
  unixTimeSeconds → Tolk blockchain.now()).

  Pins StateCell plan shape, Tolk surface (Storage/onInternalMessage/get fun),
  op+query_id envelope, UInt64 range-check markers, schedule→createMessage
  out-message emission (dest hash stub / NoBounce / value=0 /
  PAY_FEES_SEPARATELY / op32·query_id·args body), BL-14 multi-width
  UInt{8,16,32,128,256} body/state/param (narrow/wide guards + exact cell/param
  widths; UInt128/256 are one uintN cell / loadUint(N) / int257 temp, not
  CosmWasm multi-limb; UInt256 guard is `assert (0 <= t)`, never `(1 << 256)`),
  B-RET-ABI named Struct/Enum view multi-stack returns,
  N-ANON-RESULT anonymous Array UInt64 N / Option UInt64 view returns (entry
  aggregate FC), B-OPT-STATE Option UInt64 state (Enum-shaped 2-leaf c4
  layout, none default, payload zeroing, match read, tolk→fif), Option Int64
  state as tag+signed int64 cell (not a UInt64 alias and not CosmWasm
  Regions), Option UInt128 state as unsigned tag uint64 + one uint128
  payload cell (not CosmWasm 2-limb / not two UInt64 leaves; Option Int8 /
  Option UInt256 / Option UInt128 return stay FC; Option Int64 view return
  is 2-leaf tag+payload),
  B-CTX-OPEN context.unixTimeSeconds → Plan blockUnixTimeSeconds / Tolk
  blockchain.now() (entry+view; caller/unknown FC), Array Int64 N as N
  consecutive int64 c4 cells (isInt / loadInt; not a UInt64 alias and not
  CosmWasm Regions; Array Int64 24 stays uniformly isInt), Array UInt128 N
  as N consecutive uint128 c4 cells (leafByteWidth=16 / loadUint(128) /
  int257 0≤t<2^128; not CosmWasm 2-limb Regions and not two UInt64 leaves;
  cell budget 64+Σ(field bits)≤1023 when any uint128 leaf is present,
  so N=8 and N=7+sibling UInt64 FC), dense Map
  UInt64 Int64 cap-8 as 24-leaf occ/key unsigned uint64 cells + val signed
  int64/loadInt with signedChecked* val mux (not a UInt64-value alias;
  Map Int8 / Map UInt128 / Map Int64 return stay FC), and explicit
  fail-closed boundaries (sync call,
  Int128/256, Array Int64 return, Array UInt256, Array UInt128 return,
  Array/Map/Option of Int8/16/32 and Map of UInt128 / Opt of UInt256,
  UInt128/256 shifts/bitwise, Map/Bytes returns, N>8,
  nested/narrow-element containers, Option-of-non-scalar params, invariants,
  Field). Principal 9-leaf wire identity is admitted (T4; ≠address).
  CAP-5 `pf.crypto.sha256` UInt256→UInt256 via Tolk `slice.bitsHash()` /
  TVM `SHA256U` over the Semantic 32-byte LE image (`string_hash` /
  keccak256 / siblings stay fail closed).
  CAP-X-BYTES `pf.crypto.sha256Bytes` Bytes N→UInt256 (`1 ≤ N ≤ 127`,
  one-cell 8N-bit `bitsHash`/`SHA256U`; N=128 and siblings stay FC).

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

/-- CAP-5: exact `pf.crypto.sha256` UInt256→UInt256 is admitted as Tolk
    `slice.bitsHash()` (TVM `SHA256U`) over the Semantic 32-byte LE image.
    `string_hash` must not appear. keccak256 / siblings / wrong width stay
    named FC. Product resolve admits this leaf (no `effect.synchronous-call`). -/
private unsafe def testCryptoSha256Admitted
    (session : Language.Loader.ParserSession) : IO Unit := do
  let expectPlanFc (programName pathLabel moduleName body needle : String)
      (also : String := "") : IO Unit := do
    let src := wrapProgram programName body
    let compiled ← compileSource session src moduleName pathLabel
    -- Sibling QNs that are not host-syscall leaves still contribute
    -- effect.synchronous-call; pin the Plan diagnostic on the engineering
    -- path. keccak256 / wrong-width sha256 / schedule reach product Plan.
    match planTon compiled with
    | .error e =>
        if e.render.contains needle then
          unless also.isEmpty do
            expect (e.render.contains also)
              s!"{programName} Plan FC must contain '{also}', got: {e.render}"
        else if e.render.contains "effect.synchronous-call" then
          match engineeringPlanFromCompiled compiled with
          | .error e2 =>
              expect (e2.render.contains needle)
                s!"{programName} Plan FC must contain '{needle}', got: {e2.render}"
              unless also.isEmpty do
                expect (e2.render.contains also)
                  s!"{programName} Plan FC must contain '{also}', got: {e2.render}"
          | .ok _ =>
              throw <| IO.userError
                s!"{programName} must Plan fail closed after resolver sync-call decline"
        else
          throw <| IO.userError
            s!"{programName} Plan FC must contain '{needle}', got: {e.render}"
    | .ok _ =>
        throw <| IO.userError
          s!"{programName} must Plan fail closed (no Ton crypto host)"
  let src := wrapProgram "Sha256Ton" <|
    "  state last : UInt256\n\n" ++
    "  init() do\n" ++
    "    last := 0\n\n" ++
    "  entry probe(x : UInt256) : UInt256 do\n" ++
    "    let h : UInt256 := call pf.crypto.sha256(x)\n" ++
    "    last := h\n" ++
    "    return last\n\n" ++
    "  view get() : UInt256 do\n" ++
    "    return last\n"
  let compiled ← compileSource session src "Examples.Sha256Ton" "<ton-sha256>"
  let plan ← liftResult <| planTon compiled
  let some probe := plan.entries.find? (·.name == "probe") |
    throw <| IO.userError "Sha256Ton: missing probe"
  let hasSha256 := probe.body.any fun s =>
    match s with
    | .store op =>
        match op.value with
        | .sha256 _ => true
        | _ => false
    | .returnValue (.sha256 _) => true
    | _ => false
  expect hasSha256 "Sha256Ton: plan must contain Expr.sha256"
  match validatePlan plan with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"Sha256Ton plan must validate: {e.render}"
  let ir ← liftResult <| irTon compiled
  let some probeIR := ir.methods.find? (·.name == "probe") |
    throw <| IO.userError "Sha256Ton: missing IR probe"
  expect (probeIR.operations.any fun
      | .sha256 _ _ => true
      | _ => false)
    "Sha256Ton IR must carry Operation.sha256"
  let files ← liftResult <| filesTon compiled
  let tolk ← findFile files "Sha256Ton.tolk"
  expect (tolk.contains "bitsHash()")
    "Sha256Ton Tolk must call slice.bitsHash() (TVM SHA256U)"
  expect (tolk.contains "beginParse()")
    "Sha256Ton Tolk must hash a slice built from the UInt256 LE image"
  expect (tolk.contains "& 255")
    "Sha256Ton Tolk must extract LE bytes of the UInt256 word"
  expect (tolk.contains ">> 248")
    "Sha256Ton Tolk must store all 32 LE bytes (last shift is 248)"
  expect (!tolk.contains "string_hash")
    "Sha256Ton Tolk must not emit FunC string_hash (cell-hash-flavored name)"
  expect (!tolk.contains "HASHCU")
    "Sha256Ton Tolk must not emit cell representation hash HASHCU"
  expect (!tolk.contains "HASHBU")
    "Sha256Ton Tolk must not emit slice representation hash HASHBU"
  -- Host-optional locked tolk → .fif (same env as ClockBox / OptionState).
  let home ← IO.getEnv "HOME"
  let toolRoot ← match ← IO.getEnv "PROOF_FORGE_TOOL_ROOT" with
    | some r => pure r
    | none =>
        match home with
        | some h =>
            let linux := s!"{h}/.cache/proof-forge-v2/tool-root/linux-x86_64"
            let darwin := s!"{h}/.cache/proof-forge-v2/tool-root/darwin-arm64"
            if (← (System.FilePath.mk (linux ++ "/tolk")).pathExists) then
              pure linux
            else
              pure darwin
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
      args := #["-d", "/tmp/pf-ton-sha256.XXXXXX"]
    }
    unless tmp.exitCode == 0 do
      throw <| IO.userError s!"mktemp failed: {tmp.stderr}"
    let staging := (tmp.stdout.trim)
    try
      IO.FS.writeFile (System.FilePath.mk staging / "Sha256Ton.tolk") tolk
      let proc ← IO.Process.output {
        cmd := tolkBin.toString
        args := #["-o", "Sha256Ton.fif", "Sha256Ton.tolk"]
        cwd := some (System.FilePath.mk staging)
        env := #[("TOLK_STDLIB", stdlib), ("LC_ALL", "C"), ("TZ", "UTC")]
      }
      unless proc.exitCode == 0 do
        throw <| IO.userError
          s!"locked tolk failed to compile Sha256Ton.tolk:\n{proc.stderr}{proc.stdout}"
      let fifPath := System.FilePath.mk staging / "Sha256Ton.fif"
      unless ← fifPath.pathExists do
        throw <| IO.userError "tolk returned no Sha256Ton.fif"
      let fifBytes ← IO.FS.readFile fifPath
      expect (fifBytes.length > 0) "Sha256Ton.fif must be non-empty"
      IO.println "  ✓ Sha256Ton locked tolk → .fif"
    finally
      let _ ← IO.Process.output {
        cmd := "rm"
        args := #["-rf", staging]
      }
  else
    IO.println "  · Sha256Ton tolk→fif skipped (tool-root/tolk or stdlib absent)"
  expectPlanFc "Keccak256Ton" "<ton-keccak256>" "Examples.Keccak256Ton"
    ("  state last : UInt256\n\n" ++
      "  init() do\n" ++
      "    last := 0\n\n" ++
      "  entry probe(x : UInt256) : UInt256 do\n" ++
      "    let h : UInt256 := call pf.crypto.keccak256(x)\n" ++
      "    last := h\n" ++
      "    return h\n\n" ++
      "  view get() : UInt256 do\n" ++
      "    return last\n")
    "has no Ton host binding" "keccak256"
  expectPlanFc "Sha256TonHashNoPad" "<ton-sha256-hashnopad>"
    "Examples.Sha256TonHashNoPad"
    ("  state last : UInt256\n\n" ++
      "  init() do\n" ++
      "    last := 0\n\n" ++
      "  entry probe(x : UInt256) : UInt256 do\n" ++
      "    let h : UInt256 := call pf.crypto.hashNoPad(x)\n" ++
      "    last := h\n" ++
      "    return h\n\n" ++
      "  view get() : UInt256 do\n" ++
      "    return last\n")
    "has no Ton host binding"
  expectPlanFc "Sha256TonU64" "<ton-sha256-u64>" "Examples.Sha256TonU64"
    ("  state pad : UInt64\n\n" ++
      "  init() do\n" ++
      "    pad := 0\n\n" ++
      "  entry probe() : UInt64 do\n" ++
      "    let w : UInt64 := 0\n" ++
      "    let h : UInt64 := call pf.crypto.sha256(w)\n" ++
      "    return pad\n\n" ++
      "  view get() : UInt64 do\n" ++
      "    return pad\n")
    "pf.crypto.sha256 requires exactly one UInt256 argument and UInt256 result"
  expectPlanFc "Sha256TonSched" "<ton-sha256-sched>" "Examples.Sha256TonSched"
    ("  state last : UInt256\n\n" ++
      "  init() do\n" ++
      "    last := 0\n\n" ++
      "  entry probe(x : UInt256) : UInt256 do\n" ++
      "    schedule pf.crypto.sha256(x)\n" ++
      "    last := x\n" ++
      "    return x\n\n" ++
      "  view get() : UInt256 do\n" ++
      "    return last\n")
    "pf.crypto calls cannot be scheduled"
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
  IO.println "  ✓ pf.crypto.sha256 → bitsHash/SHA256U; keccak256/siblings stay FC"

/-- CAP-X-BYTES: exact `pf.crypto.sha256Bytes(Bytes N) -> UInt256` with
    `N ≤ 127` (1023-bit TVM cell / one-slice SHA256U). Independent Plan
    node `.sha256Bytes`. `string_hash` / `HASHCU` / `HASHBU` never emit.
    Legacy UInt256 `.sha256` leaf is unchanged. -/
private unsafe def testCryptoSha256BytesAdmitted
    (session : Language.Loader.ParserSession) : IO Unit := do
  let expectPlanFc (programName pathLabel moduleName body needle : String)
      (also : String := "") : IO Unit := do
    let src := wrapProgram programName body
    let compiled ← compileSource session src moduleName pathLabel
    match planTon compiled with
    | .error e =>
        if e.render.contains needle then
          unless also.isEmpty do
            expect (e.render.contains also)
              s!"{programName} Plan FC must contain '{also}', got: {e.render}"
        else if e.render.contains "effect.synchronous-call" then
          match engineeringPlanFromCompiled compiled with
          | .error e2 =>
              expect (e2.render.contains needle)
                s!"{programName} Plan FC must contain '{needle}', got: {e2.render}"
              unless also.isEmpty do
                expect (e2.render.contains also)
                  s!"{programName} Plan FC must contain '{also}', got: {e2.render}"
          | .ok _ =>
              throw <| IO.userError
                s!"{programName} must Plan fail closed after resolver sync-call decline"
        else
          throw <| IO.userError
            s!"{programName} Plan FC must contain '{needle}', got: {e.render}"
    | .ok _ =>
        throw <| IO.userError
          s!"{programName} must Plan fail closed (no Ton crypto host)"
  let hasSha256BytesStmt (s : Statement) : Bool :=
    match s with
    | .store op =>
        match op.value with
        | .sha256Bytes _ => true
        | _ => false
    | .returnValue (.sha256Bytes _) => true
    | _ => false
  -- Positive: Bytes 4 state → dedicated Plan node + bitsHash, not string_hash.
  -- Small N keeps c4 `__layout`+fields well under 1023 bits (hash cell is
  -- independent: 8*4 = 32).
  let src := wrapProgram "Sha256BytesTon" <|
    "  state data : Bytes 4\n" ++
    "  state last : UInt256\n\n" ++
    "  init() do\n" ++
    "    data[0] := 0\n" ++
    "    data[1] := 0\n" ++
    "    data[2] := 0\n" ++
    "    data[3] := 0\n" ++
    "    last := 0\n\n" ++
    "  entry probe() : UInt256 do\n" ++
    "    let h : UInt256 := call pf.crypto.sha256Bytes(data)\n" ++
    "    last := h\n" ++
    "    return last\n\n" ++
    "  view get() : UInt256 do\n" ++
    "    return last\n"
  let compiled ← compileSource session src "Examples.Sha256BytesTon" "<ton-sha256-bytes>"
  let plan ← liftResult <| planTon compiled
  let some probe := plan.entries.find? (·.name == "probe") |
    throw <| IO.userError "Sha256BytesTon: missing probe"
  expect (probe.body.any hasSha256BytesStmt)
    "Sha256BytesTon: plan must contain Expr.sha256Bytes"
  expect (!probe.body.any fun s =>
      match s with
      | .store op =>
          match op.value with
          | .sha256 _ => true
          | _ => false
      | .returnValue (.sha256 _) => true
      | _ => false)
    "Sha256BytesTon: must not reuse the UInt256 Expr.sha256 node"
  match validatePlan plan with
  | .ok () => pure ()
  | .error e =>
      throw <| IO.userError s!"Sha256BytesTon plan must validate: {e.render}"
  let ir ← liftResult <| irTon compiled
  let some probeIR := ir.methods.find? (·.name == "probe") |
    throw <| IO.userError "Sha256BytesTon: missing IR probe"
  expect (probeIR.operations.any fun
      | .sha256Bytes _ _ => true
      | _ => false)
    "Sha256BytesTon IR must carry Operation.sha256Bytes"
  expect (!probeIR.operations.any fun
      | .sha256 _ _ => true
      | _ => false)
    "Sha256BytesTon IR must not reuse Operation.sha256"
  let files ← liftResult <| filesTon compiled
  let tolk ← findFile files "Sha256BytesTon.tolk"
  expect (tolk.contains "bitsHash()")
    "Sha256BytesTon Tolk must call slice.bitsHash() (TVM SHA256U)"
  expect (tolk.contains "beginParse()")
    "Sha256BytesTon Tolk must hash a slice built from the Bytes N image"
  expect (tolk.contains "storeUint")
    "Sha256BytesTon Tolk must store unsigned byte bits into the hash cell"
  expect (!tolk.contains "string_hash")
    "Sha256BytesTon Tolk must not emit FunC string_hash"
  expect (!tolk.contains "HASHCU")
    "Sha256BytesTon Tolk must not emit cell representation hash HASHCU"
  expect (!tolk.contains "HASHBU")
    "Sha256BytesTon Tolk must not emit slice representation hash HASHBU"
  -- N=127 (8*127=1016 ≤ 1023) via state flatten (param flatten is
  -- maxParams=64 and would mask the hash-cell bound).
  let src127 := wrapProgram "Sha256BytesTon127" <|
    "  state data : Bytes 127\n" ++
    "  state last : UInt256\n\n" ++
    "  init() do\n" ++
    "    last := 0\n\n" ++
    "  entry probe() : UInt256 do\n" ++
    "    let h : UInt256 := call pf.crypto.sha256Bytes(data)\n" ++
    "    last := h\n" ++
    "    return last\n\n" ++
    "  view get() : UInt256 do\n" ++
    "    return last\n"
  let compiled127 ← compileSource session src127 "Examples.Sha256BytesTon127"
    "<ton-sha256-bytes-127>"
  let plan127 ← liftResult <| planTon compiled127
  let some probe127 := plan127.entries.find? (·.name == "probe") |
    throw <| IO.userError "Sha256BytesTon127: missing probe"
  expect (probe127.body.any hasSha256BytesStmt)
    "Sha256BytesTon127: plan must contain Expr.sha256Bytes"
  let files127 ← liftResult <| filesTon compiled127
  let tolk127 ← findFile files127 "Sha256BytesTon127.tolk"
  expect (tolk127.contains "bitsHash()")
    "Sha256BytesTon127 Tolk must call slice.bitsHash()"
  expect (!tolk127.contains "string_hash")
    "Sha256BytesTon127 Tolk must not emit string_hash"
  -- Integer argument stays at the shared-core Bytes gate (never a host CALL).
  let intSrc := wrapProgram "Sha256BytesTonInt" <|
    "  state pad : UInt64\n\n" ++
    "  init() do\n" ++
    "    pad := 0\n\n" ++
    "  entry probe(x : UInt64) : UInt256 do\n" ++
    "    let h : UInt256 := call pf.crypto.sha256Bytes(x)\n" ++
    "    return h\n\n" ++
    "  view get() : UInt64 do\n" ++
    "    return pad\n"
  match ← session.selectProgramV1 intSrc "<ton-sha256-bytes-int>"
      "Examples.Sha256BytesTonInt" none with
  | .error e =>
      throw <| IO.userError
        s!"Sha256BytesTonInt must load, got {e.render}"
  | .ok validated =>
      match Compiler.compileValidatedSourceV1 validated with
      | .ok _ =>
          throw <| IO.userError
            "Sha256BytesTonInt must fail at Normalize (integer is not Bytes)"
      | .error e =>
          expect (e.render.contains "sha256Bytes" && e.render.contains "Bytes")
            s!"Sha256BytesTonInt must cite sha256Bytes/Bytes, got {e.render}"
  -- Zero args / two Bytes args / non-UInt256 result / N=128 / near-miss QN.
  expectPlanFc "Sha256BytesTonZero" "<ton-sha256-bytes-zero>"
    "Examples.Sha256BytesTonZero"
    ("  state last : UInt256\n\n" ++
      "  init() do\n" ++
      "    last := 0\n\n" ++
      "  entry probe() : UInt256 do\n" ++
      "    let h : UInt256 := call pf.crypto.sha256Bytes()\n" ++
      "    last := h\n" ++
      "    return last\n\n" ++
      "  view get() : UInt256 do\n" ++
      "    return last\n")
    "pf.crypto.sha256Bytes requires exactly one Bytes N argument and UInt256 result"
  expectPlanFc "Sha256BytesTonTwo" "<ton-sha256-bytes-two>"
    "Examples.Sha256BytesTonTwo"
    ("  state a : Bytes 4\n" ++
      "  state b : Bytes 4\n" ++
      "  state last : UInt256\n\n" ++
      "  init() do\n" ++
      "    last := 0\n\n" ++
      "  entry probe() : UInt256 do\n" ++
      "    let h : UInt256 := call pf.crypto.sha256Bytes(a, b)\n" ++
      "    last := h\n" ++
      "    return last\n\n" ++
      "  view get() : UInt256 do\n" ++
      "    return last\n")
    "pf.crypto.sha256Bytes requires exactly one Bytes N argument and UInt256 result"
  expectPlanFc "Sha256BytesTonU64" "<ton-sha256-bytes-u64>"
    "Examples.Sha256BytesTonU64"
    ("  state data : Bytes 4\n" ++
      "  state pad : UInt64\n\n" ++
      "  init() do\n" ++
      "    pad := 0\n\n" ++
      "  entry probe() : UInt64 do\n" ++
      "    let h : UInt64 := call pf.crypto.sha256Bytes(data)\n" ++
      "    return pad\n\n" ++
      "  view get() : UInt64 do\n" ++
      "    return pad\n")
    "pf.crypto.sha256Bytes requires exactly one Bytes N argument and UInt256 result"
  expectPlanFc "Sha256BytesTon128" "<ton-sha256-bytes-128>"
    "Examples.Sha256BytesTon128"
    ("  state data : Bytes 128\n" ++
      "  state last : UInt256\n\n" ++
      "  init() do\n" ++
      "    last := 0\n\n" ++
      "  entry probe() : UInt256 do\n" ++
      "    let h : UInt256 := call pf.crypto.sha256Bytes(data)\n" ++
      "    last := h\n" ++
      "    return last\n\n" ++
      "  view get() : UInt256 do\n" ++
      "    return last\n")
    "1023-bit TVM cell capacity" "N ≤ 127"
  expectPlanFc "Sha256BytesTonNear" "<ton-sha256-bytes-near>"
    "Examples.Sha256BytesTonNear"
    ("  state last : UInt256\n\n" ++
      "  init() do\n" ++
      "    last := 0\n\n" ++
      "  entry probe(x : UInt256) : UInt256 do\n" ++
      "    let h : UInt256 := call pf.crypto.sha256Bytess(x)\n" ++
      "    last := h\n" ++
      "    return h\n\n" ++
      "  view get() : UInt256 do\n" ++
      "    return last\n")
    "has no Ton host binding" "sha256Bytess"
  IO.println "  ✓ pf.crypto.sha256Bytes → bitsHash/SHA256U; N=128/arity/siblings FC"

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

/-- Array Int8 / Map Int32 / Option Int8 stay fail closed (not Array-of-Int64). -/
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
  IO.println "  ✓ Array Int8 / Map Int32 / Option Int8 stay fail closed"

/-- Array Int64 N = N consecutive 8-byte signed c4 cells (`isInt`, Tolk
    `int64` / `loadInt`). Same flatten as Array UInt64; not a packed array,
    not a UInt64 alias, and not CosmWasm Regions. -/
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
  let compiled ← compileSource session src "Examples.ArrInt64" "<ton-arr-int64>"
  let plan ← liftResult <| planTon compiled
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
        leaves.size == 2 && leaves.all (fun st => st.byteWidth == 8)
    | _ => false
  expect initAtomic "ArrInt64 init storeAtomic 2 signed 8-byte leaves"
  let some set0 := plan.entries.find? (·.name == "set0") |
    throw <| IO.userError "ArrInt64 missing set0"
  expect (set0.resultKind == MethodResultKind.int64) "ArrInt64 entry result Int64"
  let setAtomic := set0.body.any fun s =>
    match s with
    | .storeAtomic leaves =>
        leaves.size == 2 && leaves.all (fun st => st.byteWidth == 8)
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
  let files ← liftResult <| filesTon compiled
  let tolk ← findFile files "ArrInt64.tolk"
  let abi ← findFile files "ArrInt64.ton-abi.json"
  expect (tolk.contains "slots_0: int64") "ArrInt64 Tolk slots_0: int64"
  expect (tolk.contains "slots_1: int64") "ArrInt64 Tolk slots_1: int64"
  expect (!tolk.contains "slots_0: uint64")
    "ArrInt64 Tolk must not alias slots_0 as uint64"
  expect (tolk.contains "body.loadInt(64)") "ArrInt64 param loadInt(64)"
  expect (abi.contains "\"type\":\"int64\"") "ArrInt64 ABI JSON type int64"
  expect (abi.contains "\"returns\":\"int64\"") "ArrInt64 ABI returns int64"
  IO.println "  ✓ Array Int64 2 as N×int64 c4 cells"

/-- Array Int64 24 must stay 24 uniform signed cells. Map val-only isInt
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
    "<ton-arr-int64-24>"
  let plan ← liftResult <| planTon compiled
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
  IO.println "  ✓ Array Int64 24 stays 24 uniform signed cells"

/-- Array Int8 stays fail closed on the historical element needle
    (`Array state element must be UInt64` is a contains-match).
    Anonymous `Array Int64 2` return stays fail closed on the existing
    UInt64-element return needle. Array UInt128 2 is admitted separately. -/
private unsafe def testArrayInt64ElementFc
    (session : Language.Loader.ParserSession) : IO Unit := do
  let arrI8 := wrapProgram "ArrI8Ton" <|
    "  state slots : Array Int8 2\n\n" ++
    "  init() do\n" ++
    "    slots[0] := 0\n" ++
    "    slots[1] := 0\n\n" ++
    "  entry set0(v : UInt64) : UInt64 do\n" ++
    "    slots[0] := 0\n" ++
    "    return v\n"
  let arrI8Compiled ← compileSource session arrI8 "Examples.ArrI8Ton" "<ton-arr-i8-el>"
  expectPlanErrorContaining "ArrI8" "Array state element must be UInt64"
    (planTon arrI8Compiled)
  IO.println "  ✓ Array Int8 stay fail closed"

/-- Array UInt128 N = N consecutive 16-byte unsigned c4 cells (`uint128` /
    `loadUint(128)` / int257 `0≤t<2^128`). Same flatten as Array
    UInt64/Int64, `leafByteWidth=16`, `isInt=false`. Not CosmWasm 2-limb
    Regions and not two UInt64 leaves. -/
private unsafe def testArrayUInt128State
    (session : Language.Loader.ParserSession) : IO Unit := do
  let src := wrapProgram "ArrU128" <|
    "  state slots : Array UInt128 2\n\n" ++
    "  init() do\n" ++
    "    slots[0] := 0\n" ++
    "    slots[1] := 0\n\n" ++
    "  entry set0(v : UInt128) : UInt128 do\n" ++
    "    slots[0] := v\n" ++
    "    return slots[0]\n\n" ++
    "  view get() : UInt128 do\n" ++
    "    return slots[1]\n"
  let compiled ← compileSource session src "Examples.ArrU128" "<ton-arr-u128>"
  let plan ← liftResult <| planTon compiled
  expect (plan.storage.fields.size == 2) "ArrU128 fields.size==2"
  expect (plan.storage.fields[0]!.name == "slots_0") "ArrU128 slots_0"
  expect (plan.storage.fields[1]!.name == "slots_1") "ArrU128 slots_1"
  expect (plan.storage.fields[0]!.byteWidth == 16) "ArrU128 slots_0 byteWidth=16"
  expect (plan.storage.fields[1]!.byteWidth == 16) "ArrU128 slots_1 byteWidth=16"
  expect (!plan.storage.fields[0]!.isInt) "ArrU128 slots_0 unsigned"
  expect (!plan.storage.fields[1]!.isInt) "ArrU128 slots_1 unsigned"
  expect (layoutFieldTypeSuffix 16 false == "u128-le")
    "ArrU128 layout suffix is u128-le (not u64-le / not 2-limb)"
  expect (layoutFieldTypeSuffix
      plan.storage.fields[0]!.byteWidth plan.storage.fields[0]!.isInt == "u128-le")
    "ArrU128 field ABI suffix is u128-le"
  let initAtomic := plan.initializer.body.any fun s =>
    match s with
    | .storeAtomic leaves =>
        leaves.size == 2 && leaves.all (fun st => st.byteWidth == 16)
    | _ => false
  expect initAtomic "ArrU128 init storeAtomic 2 unsigned 16-byte leaves"
  let some set0 := plan.entries.find? (·.name == "set0") |
    throw <| IO.userError "ArrU128 missing set0"
  expect (set0.resultKind == MethodResultKind.uint128) "ArrU128 entry result UInt128"
  let setAtomic := set0.body.any fun s =>
    match s with
    | .storeAtomic leaves =>
        leaves.size == 2 && leaves.all (fun st => st.byteWidth == 16)
    | _ => false
  expect setAtomic "ArrU128 entry storeAtomic 2 unsigned 16-byte leaves"
  let hasUInt128Return := set0.body.any fun s =>
    match s with
    | .returnValue _ => true
    | _ => false
  expect hasUInt128Return "ArrU128 entry returnValue UInt128 IndexGet"
  let some get := plan.entries.find? (·.name == "get") |
    throw <| IO.userError "ArrU128 missing get"
  expect (get.mode == .view && get.resultKind == MethodResultKind.uint128)
    "ArrU128 view result UInt128"
  match get.body[get.body.size - 1]! with
  | .returnValue _ => pure ()
  | _ => throw <| IO.userError "ArrU128 view must returnValue UInt128 IndexGet"
  match validatePlan plan with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"ArrU128 plan must validate: {e.render}"
  let files ← liftResult <| filesTon compiled
  let tolk ← findFile files "ArrU128.tolk"
  let abi ← findFile files "ArrU128.ton-abi.json"
  expect (tolk.contains "slots_0: uint128") "ArrU128 Tolk slots_0: uint128"
  expect (tolk.contains "slots_1: uint128") "ArrU128 Tolk slots_1: uint128"
  expect (!tolk.contains "slots_0: uint64")
    "ArrU128 Tolk must not alias slots_0 as uint64"
  expect (!tolk.contains "slots_0_lo" && !tolk.contains "slots_0_hi" &&
      !tolk.contains "slots_0_l0" && !tolk.contains "slots_0_l1")
    "ArrU128 Tolk must not emit CosmWasm 2-limb names"
  expect (tolk.contains "body.loadUint(128)") "ArrU128 param loadUint(128)"
  expect (tolk.contains "(1 << 128)") "ArrU128 UInt128 range guard"
  expect (abi.contains "\"type\":\"uint128\"") "ArrU128 ABI JSON type uint128"
  expect (abi.contains "\"returns\":\"uint128\"") "ArrU128 ABI returns uint128"
  IO.println "  ✓ Array UInt128 2 as N×uint128 c4 cells"

/-- Array UInt128 8 is 64+8*128=1088 bits and exceeds the honest 1023-bit
    c4 cell (shared `__layout` uint64). Fail closed on the budget needle,
    not the historical element needle, and do not pack 2×UInt64 limbs. -/
private unsafe def testArrayUInt128CellBudget
    (session : Language.Loader.ParserSession) : IO Unit := do
  let src := wrapProgram "ArrU128N8" <|
    "  state slots : Array UInt128 8\n\n" ++
    "  init() do\n" ++
    "    slots[0] := 0\n\n" ++
    "  entry set0(v : UInt128) : UInt128 do\n" ++
    "    slots[0] := v\n" ++
    "    return slots[0]\n\n" ++
    "  view get() : UInt128 do\n" ++
    "    return slots[0]\n"
  let compiled ← compileSource session src "Examples.ArrU128N8" "<ton-arr-u128-n8>"
  match planTon compiled with
  | .error (.planInvariant .ton msg) =>
      expect (msg.contains "Array UInt128 exceeds the 1023-bit c4 cell budget")
        s!"ArrU128 N=8 must cite cell budget, got: {msg}"
      expect (!msg.contains "Array state element must be UInt64")
        s!"ArrU128 N=8 must not reuse the element needle, got: {msg}"
  | .error e => throw <| IO.userError s!"ArrU128 N=8: unexpected {e.render}"
  | .ok _ => throw <| IO.userError "ArrU128 N=8: expected FC, got ok"
  IO.println "  ✓ Array UInt128 8 exceeds 1023-bit c4 cell budget"

/-- Array UInt128 7 + sibling UInt64 is 64+7*128+64=1024 bits and exceeds
    the shared c4 cell. Fail closed on the same budget needle. -/
private unsafe def testArrayUInt128SiblingCellBudget
    (session : Language.Loader.ParserSession) : IO Unit := do
  let src := wrapProgram "ArrU128N7Pad" <|
    "  state slots : Array UInt128 7\n" ++
    "  state pad : UInt64\n\n" ++
    "  init() do\n" ++
    "    pad := 0\n\n" ++
    "  entry set0(v : UInt128) : UInt128 do\n" ++
    "    slots[0] := v\n" ++
    "    return slots[0]\n\n" ++
    "  view get() : UInt128 do\n" ++
    "    return slots[0]\n"
  let compiled ← compileSource session src "Examples.ArrU128N7Pad"
    "<ton-arr-u128-n7-pad>"
  match planTon compiled with
  | .error (.planInvariant .ton msg) =>
      expect (msg.contains "Array UInt128 exceeds the 1023-bit c4 cell budget")
        s!"ArrU128 N=7+pad must cite cell budget, got: {msg}"
      expect (!msg.contains "Array state element must be UInt64")
        s!"ArrU128 N=7+pad must not reuse the element needle, got: {msg}"
  | .error e => throw <| IO.userError s!"ArrU128 N=7+pad: unexpected {e.render}"
  | .ok _ => throw <| IO.userError "ArrU128 N=7+pad: expected FC, got ok"
  IO.println "  ✓ Array UInt128 7 + UInt64 exceeds 1023-bit c4 cell budget"

/-- Anonymous Array UInt128 view return stays UInt64-only after container
    layout started admitting UInt128 elements. -/
private unsafe def testArrayUInt128ReturnFc
    (session : Language.Loader.ParserSession) : IO Unit := do
  let src := wrapProgram "ArrU128Ret" <|
    "  state slots : Array UInt128 2\n\n" ++
    "  init() do\n" ++
    "    slots[0] := 0\n" ++
    "    slots[1] := 0\n\n" ++
    "  view peek() : Array UInt128 2 do\n" ++
    "    return slots\n"
  let compiled ← compileSource session src "Examples.ArrU128Ret" "<ton-arr-u128-ret>"
  expectPlanErrorContaining "ArrU128Ret"
    "anonymous Array return requires UInt64 or Int64 elements"
    (planTon compiled)
  IO.println "  ✓ Array UInt128 return stays fail closed"

/-- 0/1 word select that preserves a signed Int64 payload (no uint64
    range). Matches mapSelectLeafV1 `signed := true`. -/
private def isSignedWordSelect : Expr → Bool
  | .signedCheckedAdd (.signedCheckedMul _ _) (.signedCheckedMul _ _) => true
  | _ => false

/-- 0/1 word select that attaches uint64RangeCheck. Occ/key stay on this
    form; val slots of Map UInt64 Int64 must not. -/
private def isUnsignedWordSelect : Expr → Bool
  | .checkedAdd (.checkedMul _ _) (.checkedMul _ _) => true
  | _ => false

private def storeAtomicLeaves (body : Array Statement) : Option (Array Store) :=
  body.findSome? fun s =>
    match s with
    | .storeAtomic leaves => some leaves
    | _ => none

/-- Collect Plan exprs so get's match payload mux is visible. -/
private partial def statementExprs : Statement → Array Expr
  | .store op => #[op.value]
  | .storeAtomic leaves => leaves.map (·.value)
  | .returnValue v => #[v]
  | .returnAggregate leaves _ => leaves
  | .returnNone => #[]
  | .assert c => #[c]
  | .emitEvent _ args => args
  | .revertError _ args => args
  | .ifThenElse c t e =>
      #[c] ++ t.flatMap statementExprs ++ e.flatMap statementExprs
  | .switchOn s cases d =>
      #[s] ++ cases.flatMap (fun (_, b) => b.flatMap statementExprs) ++
        d.flatMap statementExprs
  | .forLoop _ initial cond upd _ body =>
      #[initial, cond, upd] ++ body.flatMap statementExprs
  | .promiseAccount _ _ args => args

private def expectMapInt64ValMux
    (label : String) (leaves : Array Store) : IO Unit := do
  expect (leaves.size == 24) s!"{label}: storeAtomic must write 24 leaves"
  for i in [0:24] do
    let some st := leaves[i]? |
      throw <| IO.userError s!"{label}: missing store leaf {i}"
    expect (st.byteWidth == 8) s!"{label}: leaf {i} byteWidth=8"
    if i % 3 == 2 then
      expect (isSignedWordSelect st.value)
        s!"{label}: val slot {i} must be signedCheckedMul/Add (not uint64 mux)"
      expect (!isUnsignedWordSelect st.value)
        s!"{label}: val slot {i} must not use unsigned checkedMul/Add"
    else if i % 3 == 1 then
      expect (isUnsignedWordSelect st.value)
        s!"{label}: key slot {i} must stay unsigned checkedMul/Add"
      expect (!isSignedWordSelect st.value)
        s!"{label}: key slot {i} must not use signedChecked*"

/-- TON-MAP-INT: Map UInt64 Int64 state = cap-8 24-leaf occ/key/val flatten.
    occ/key stay unsigned uint64 cells; only val slots (`i % 3 == 2`) are
    signed int64/loadInt and signedChecked* mux — not a UInt64-value
    alias. put(v) + putNeg(-1) pin the loadInt and negative-literal
    val lanes. get match returns Int64; anonymous Map Int64 return stays FC. -/
private unsafe def testMapInt64State
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrapProgram "MapInt64" <|
    "  state m : Map UInt64 Int64\n\n" ++
    "  init() do\n" ++
    "    m := Map.empty()\n\n" ++
    "  entry put(k : UInt64, v : Int64) : Int64 do\n" ++
    "    m[k] := v\n" ++
    "    return v\n\n" ++
    "  entry putNeg(k : UInt64) : Int64 do\n" ++
    "    m[k] := -1\n" ++
    "    return -1\n\n" ++
    "  view get(k : UInt64) : Int64 do\n" ++
    "    match m[k] with\n" ++
    "    | Option.some(x) => do\n" ++
    "      return x\n" ++
    "    | _ => do\n" ++
    "      return 0\n"
  let compiled ← compileSource session source "Examples.MapInt64"
    "<ton-map-int64>"
  let plan ← liftResult <| planTon compiled
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
  let mapAtomic (body : Array Statement) : Bool :=
    body.any fun s =>
      match s with
      | .storeAtomic leaves =>
          leaves.size == 24 && leaves.all (fun st => st.byteWidth == 8)
      | _ => false
  expect (mapAtomic plan.initializer.body)
    "MapInt64 init empty must storeAtomic 24×8"
  let some put := plan.entries.find? (·.name == "put") |
    throw <| IO.userError "MapInt64 missing put"
  expect (put.resultKind == MethodResultKind.int64) "MapInt64 put result Int64"
  let some putLeaves := storeAtomicLeaves put.body |
    throw <| IO.userError "MapInt64 put must storeAtomic 24×8"
  expectMapInt64ValMux "MapInt64 put" putLeaves
  -- loadInt param is the write operand of every val-slot signed select.
  let putValIsParam := (List.range 8).all fun e =>
    match putLeaves[e * 3 + 2]? with
    | some st =>
        match st.value with
        | .signedCheckedAdd (.signedCheckedMul _ (.param _)) _ => true
        | _ => false
    | none => false
  expect putValIsParam
    "MapInt64 put val mux write operand must be the Int64 param (loadInt)"
  let some putNeg := plan.entries.find? (·.name == "putNeg") |
    throw <| IO.userError "MapInt64 missing putNeg"
  expect (putNeg.resultKind == MethodResultKind.int64) "MapInt64 putNeg result Int64"
  let some putNegLeaves := storeAtomicLeaves putNeg.body |
    throw <| IO.userError "MapInt64 putNeg must storeAtomic 24×8"
  expectMapInt64ValMux "MapInt64 putNeg" putNegLeaves
  -- `-1` folds to two's-complement UInt64 bits on the signed val lane.
  let negOne : UInt64 := (0 : UInt64) - 1
  let putNegWritesMinusOne := (List.range 8).all fun e =>
    match putNegLeaves[e * 3 + 2]? with
    | some st =>
        match st.value with
        | .signedCheckedAdd (.signedCheckedMul _ (.literal v)) _ => v == negOne
        | _ => false
    | none => false
  expect putNegWritesMinusOne
    "MapInt64 putNeg val mux must write the folded Int64 -1 literal"
  let some get := plan.entries.find? (·.name == "get") |
    throw <| IO.userError "MapInt64 missing get"
  expect (get.mode == .view && get.resultKind == MethodResultKind.int64)
    "MapInt64 get must be view Int64 (not Map return)"
  let getExprs := get.body.flatMap statementExprs
  expect (getExprs.any isSignedWordSelect)
    "MapInt64 get payload mux must be signedCheckedMul/Add"
  expect (!getExprs.any isUnsignedWordSelect)
    "MapInt64 get payload must not use unsigned val mux"
  match validatePlan plan with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"MapInt64 plan must validate: {e.render}"
  let files ← liftResult <| filesTon compiled
  let tolk ← findFile files "MapInt64.tolk"
  expect (tolk.contains "m_0: uint64") "MapInt64 Tolk m_0: uint64"
  expect (tolk.contains "m_1: uint64") "MapInt64 Tolk m_1: uint64"
  expect (tolk.contains "m_2: int64") "MapInt64 Tolk m_2: int64"
  expect (tolk.contains "m_23: int64") "MapInt64 Tolk m_23: int64"
  expect (!tolk.contains "m_2: uint64")
    "MapInt64 Tolk must not alias m_2 as uint64"
  expect (tolk.contains "body.loadInt(64)") "MapInt64 param loadInt(64)"
  expect (tolk.contains "-(1 << 63)")
    "MapInt64 val mux must emit int64 range, not only (1 << 64)"
  let abi ← findFile files "MapInt64.ton-abi.json"
  expect (abi.contains "{\"name\":\"m_0\",\"type\":\"uint64\"}")
    s!"MapInt64 ABI occ m_0 must be uint64, got: {abi}"
  expect (abi.contains "{\"name\":\"m_1\",\"type\":\"uint64\"}")
    s!"MapInt64 ABI key m_1 must be uint64, got: {abi}"
  expect (abi.contains "{\"name\":\"m_2\",\"type\":\"int64\"}")
    s!"MapInt64 ABI val m_2 must be int64 (not a UInt64 alias), got: {abi}"
  expect (abi.contains "{\"name\":\"m_23\",\"type\":\"int64\"}")
    s!"MapInt64 ABI last val m_23 must be int64, got: {abi}"
  expect (abi.contains "\"returns\":\"int64\"") "MapInt64 ABI returns int64"
  IO.println "  ✓ Map UInt64 Int64 state cap-8 occ/key unsigned + val signed mux"

/-- Map Int8-value / Map UInt128-value stay fail closed on the historical
    Map-U64-U64 needle (`Map state admits only Map UInt64 UInt64` is a
    contains-match). Anonymous `Map UInt64 Int64` **view** return is
    admitted by B-RET-MAP (see testMapInt64Return). -/
private unsafe def testMapInt64ElementFc
    (session : Language.Loader.ParserSession) : IO Unit := do
  let mapI8 := wrapProgram "MapI8Ton" <|
    "  state m : Map UInt64 Int8\n\n" ++
    "  init() do\n" ++
    "    m := Map.empty()\n\n" ++
    "  entry put(k : UInt64, v : UInt64) : UInt64 do\n" ++
    "    return v\n"
  let mapI8Compiled ← compileSource session mapI8 "Examples.MapI8Ton" "<ton-map-i8>"
  expectPlanErrorContaining "MapI8" "Map state admits only Map UInt64 UInt64"
    (planTon mapI8Compiled)
  let mapU128 := wrapProgram "MapU128Ton" <|
    "  state m : Map UInt64 UInt128\n\n" ++
    "  init() do\n" ++
    "    m := Map.empty()\n\n" ++
    "  entry put(k : UInt64, v : UInt64) : UInt64 do\n" ++
    "    return v\n"
  let mapU128Compiled ← compileSource session mapU128 "Examples.MapU128Ton"
    "<ton-map-u128>"
  expectPlanErrorContaining "MapU128" "Map state admits only Map UInt64 UInt64"
    (planTon mapU128Compiled)
  IO.println "  ✓ Map Int8 / Map UInt128 stay fail closed"

/-- BL-14: UInt128 state/param/body as one uint128 cell + loadUint(128). -/
private unsafe def testUint128Abi
    (session : Language.Loader.ParserSession) : IO Unit := do
  let src := wrapProgram "Wide128" <|
    "  state s : UInt128\n\n" ++
    "  init(x : UInt128) do\n" ++
    "    s := x\n\n" ++
    "  entry go(d : UInt128) : UInt128 do\n" ++
    "    s := s + d\n" ++
    "    return s\n\n" ++
    "  view peek() : UInt128 do\n" ++
    "    return s\n"
  let compiled ← compileSource session src "Examples.Wide128" "<ton-u128>"
  let plan ← liftResult <| planTon compiled
  expect (plan.storage.fields.size == 1) "UInt128 one state field"
  expect (plan.storage.fields[0]!.byteWidth == 16) "UInt128 state byteWidth=16"
  expect (!plan.storage.fields[0]!.isInt) "UInt128 state is unsigned"
  let some go := plan.entries.find? (·.name == "go") |
    throw <| IO.userError "missing go"
  expect (go.resultKind == .uint128) "go returns UInt128"
  expect (go.params.size == 1 && go.params[0]!.byteWidth == 16)
    "go param byteWidth=16"
  let hasNarrowAdd := go.body.any fun s =>
    match s with
    | .store store =>
        match store.value with
        | .narrowCheckedAdd 128 _ _ => true
        | _ => false
    | _ => false
  expect hasNarrowAdd "entry go uses narrowCheckedAdd 128"
  match validatePlan plan with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"Wide128 plan validate: {e.render}"
  let ir ← liftResult <| irTon compiled
  let some goIR := ir.methods.find? (·.name == "go") |
    throw <| IO.userError "missing IR go"
  let hasNarrowOp := goIR.operations.any fun
    | .narrowCheckedAdd 128 _ _ _ => true
    | _ => false
  expect hasNarrowOp "IR emits narrowCheckedAdd 128"
  let files ← liftResult <| filesTon compiled
  let tolk ← findFile files "Wide128.tolk"
  expect (tolk.contains "s: uint128") "Storage field s: uint128"
  expect (tolk.contains "body.loadUint(128)") "param loadUint(128)"
  expect (tolk.contains "(1 << 128)") "UInt128 range guard bound"
  let abi ← findFile files "Wide128.ton-abi.json"
  expect (abi.contains "\"type\":\"uint128\"") "ABI uint128 type"
  expect (abi.contains "\"returns\":\"uint128\"") "ABI returns uint128"
  IO.println "  ✓ UInt128 state/param/body + int257 width guard"

/-- UInt128 body literal > 2^64-1 must emit a full decimal, not UInt64 truncation. -/
private unsafe def testUint128WideLiteral
    (session : Language.Loader.ParserSession) : IO Unit := do
  -- 2^64 = 18446744073709551616. UInt64.ofNat would wrap this to 0.
  let src := wrapProgram "WideLit" <|
    "  state s : UInt128\n\n" ++
    "  init() do\n" ++
    "    s := 0\n\n" ++
    "  entry go() : UInt128 do\n" ++
    "    s := 0x10000000000000000\n" ++
    "    return s\n\n" ++
    "  view peek() : UInt128 do\n" ++
    "    return s\n"
  let compiled ← compileSource session src "Examples.WideLit" "<ton-u128-lit>"
  let plan ← liftResult <| planTon compiled
  let some go := plan.entries.find? (·.name == "go") |
    throw <| IO.userError "missing go"
  let hasBigLit := go.body.any fun s =>
    match s with
    | .store store =>
        match store.value with
        | .bigLiteral 128 18446744073709551616 => true
        | _ => false
    | _ => false
  expect hasBigLit "entry go stores bigLiteral 128 of 2^64"
  let ir ← liftResult <| irTon compiled
  let some goIR := ir.methods.find? (·.name == "go") |
    throw <| IO.userError "missing IR go"
  let hasWideLit := goIR.operations.any fun
    | .wideLiteral _ 128 18446744073709551616 => true
    | _ => false
  expect hasWideLit "IR emits wideLiteral 128 = 18446744073709551616"
  expect (!goIR.operations.any fun
    | .literal _ 0 => true
    | _ => false)
    "IR must not truncate 2^64 to UInt64 0"
  let files ← liftResult <| filesTon compiled
  let tolk ← findFile files "WideLit.tolk"
  expect (tolk.contains "18446744073709551616")
    "Tolk prints the full UInt128 decimal (not a truncated 0)"
  expect (tolk.contains "(1 << 128)") "wideLiteral attaches UInt128 range guard"
  IO.println "  ✓ UInt128 body literal > 2^64-1 keeps full decimal"

/-- UInt128 shl/shr stay fail closed (int257 can hold the value; 64-count
    shift would drop high bits). -/
private unsafe def testUint128ShiftFc
    (session : Language.Loader.ParserSession) : IO Unit := do
  let srcShl := wrapProgram "WideShl" <|
    "  state s : UInt128\n\n" ++
    "  init(x : UInt128) do\n" ++
    "    s := x\n\n" ++
    "  entry go(d : UInt32) : UInt128 do\n" ++
    "    s := s << d\n" ++
    "    return s\n\n" ++
    "  view peek() : UInt128 do\n" ++
    "    return s\n"
  let compiledShl ← compileSource session srcShl "Examples.WideShl" "<ton-u128-shl>"
  match planTon compiledShl with
  | .error (.planInvariant .ton msg) =>
      expect (msg.contains "shift" || msg.contains "multiword")
        s!"UInt128 shl FC must cite shift/multiword, got: {msg}"
  | .error e => throw <| IO.userError s!"UInt128 shl: unexpected {e.render}"
  | .ok _ => throw <| IO.userError "UInt128 shl: expected FC, got ok"
  let srcShr := wrapProgram "WideShr" <|
    "  state s : UInt128\n\n" ++
    "  init(x : UInt128) do\n" ++
    "    s := x\n\n" ++
    "  entry go(d : UInt32) : UInt128 do\n" ++
    "    s := s >> d\n" ++
    "    return s\n\n" ++
    "  view peek() : UInt128 do\n" ++
    "    return s\n"
  let compiledShr ← compileSource session srcShr "Examples.WideShr" "<ton-u128-shr>"
  match planTon compiledShr with
  | .error (.planInvariant .ton msg) =>
      expect (msg.contains "shift" || msg.contains "multiword")
        s!"UInt128 shr FC must cite shift/multiword, got: {msg}"
  | .error e => throw <| IO.userError s!"UInt128 shr: unexpected {e.render}"
  | .ok _ => throw <| IO.userError "UInt128 shr: expected FC, got ok"
  IO.println "  ✓ UInt128 shl/shr stay fail closed"

/-- BL-14: UInt256 state/param/body as one uint256 cell + loadUint(256). -/
private unsafe def testUint256Abi
    (session : Language.Loader.ParserSession) : IO Unit := do
  let src := wrapProgram "Wide256" <|
    "  state s : UInt256\n\n" ++
    "  init(x : UInt256) do\n" ++
    "    s := x\n\n" ++
    "  entry go(d : UInt256) : UInt256 do\n" ++
    "    s := s + d\n" ++
    "    return s\n\n" ++
    "  view peek() : UInt256 do\n" ++
    "    return s\n"
  let compiled ← compileSource session src "Examples.Wide256" "<ton-u256>"
  let plan ← liftResult <| planTon compiled
  expect (plan.storage.fields.size == 1) "UInt256 one state field"
  expect (plan.storage.fields[0]!.byteWidth == 32) "UInt256 state byteWidth=32"
  expect (!plan.storage.fields[0]!.isInt) "UInt256 state is unsigned"
  let some go := plan.entries.find? (·.name == "go") |
    throw <| IO.userError "missing go"
  expect (go.resultKind == .uint256) "go returns UInt256"
  expect (go.params.size == 1 && go.params[0]!.byteWidth == 32)
    "go param byteWidth=32"
  let hasNarrowAdd := go.body.any fun s =>
    match s with
    | .store store =>
        match store.value with
        | .narrowCheckedAdd 256 _ _ => true
        | _ => false
    | _ => false
  expect hasNarrowAdd "entry go uses narrowCheckedAdd 256"
  match validatePlan plan with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"Wide256 plan validate: {e.render}"
  let ir ← liftResult <| irTon compiled
  let some goIR := ir.methods.find? (·.name == "go") |
    throw <| IO.userError "missing IR go"
  let hasNarrowOp := goIR.operations.any fun
    | .narrowCheckedAdd 256 _ _ _ => true
    | _ => false
  expect hasNarrowOp "IR emits narrowCheckedAdd 256"
  let files ← liftResult <| filesTon compiled
  let tolk ← findFile files "Wide256.tolk"
  expect (tolk.contains "s: uint256") "Storage field s: uint256"
  expect (tolk.contains "body.loadUint(256)") "param loadUint(256)"
  expect (tolk.contains "assert (0 <= t") "UInt256 nonnegative int257 guard"
  expect (!tolk.contains "(1 << 256)")
    "UInt256 must not emit unrepresentable (1 << 256)"
  let abi ← findFile files "Wide256.ton-abi.json"
  expect (abi.contains "\"type\":\"uint256\"") "ABI uint256 type"
  expect (abi.contains "\"returns\":\"uint256\"") "ABI returns uint256"
  IO.println "  ✓ UInt256 state/param/body + int257 width guard"

/-- UInt256 body literal 2^128 must emit a full decimal, not UInt64/UInt128
    truncation. -/
private unsafe def testUint256WideLiteral
    (session : Language.Loader.ParserSession) : IO Unit := do
  -- 2^128 = 340282366920938463463374607431768211456.
  -- UInt64.ofNat would wrap this to 0; a width-128 wideLiteral of this
  -- Nat would be a silent UInt128 truncate.
  let src := wrapProgram "WideLit256" <|
    "  state s : UInt256\n\n" ++
    "  init() do\n" ++
    "    s := 0\n\n" ++
    "  entry go() : UInt256 do\n" ++
    "    s := 0x100000000000000000000000000000000\n" ++
    "    return s\n\n" ++
    "  view peek() : UInt256 do\n" ++
    "    return s\n"
  let compiled ← compileSource session src "Examples.WideLit256" "<ton-u256-lit>"
  let plan ← liftResult <| planTon compiled
  let some go := plan.entries.find? (·.name == "go") |
    throw <| IO.userError "missing go"
  let hasBigLit := go.body.any fun s =>
    match s with
    | .store store =>
        match store.value with
        | .bigLiteral 256 340282366920938463463374607431768211456 => true
        | _ => false
    | _ => false
  expect hasBigLit "entry go stores bigLiteral 256 of 2^128"
  let ir ← liftResult <| irTon compiled
  let some goIR := ir.methods.find? (·.name == "go") |
    throw <| IO.userError "missing IR go"
  let hasWideLit := goIR.operations.any fun
    | .wideLiteral _ 256 340282366920938463463374607431768211456 => true
    | _ => false
  expect hasWideLit
    "IR emits wideLiteral 256 = 340282366920938463463374607431768211456"
  expect (!goIR.operations.any fun
    | .literal _ 0 => true
    | _ => false)
    "IR must not truncate 2^128 to UInt64 0"
  expect (!goIR.operations.any fun
    | .wideLiteral _ 128 340282366920938463463374607431768211456 => true
    | _ => false)
    "IR must not emit this value as width-128 wideLiteral"
  let files ← liftResult <| filesTon compiled
  let tolk ← findFile files "WideLit256.tolk"
  expect (tolk.contains "340282366920938463463374607431768211456")
    "Tolk prints the full UInt256 decimal (not a truncated 0)"
  expect (tolk.contains "assert (0 <= t")
    "wideLiteral attaches UInt256 nonnegative int257 guard"
  expect (!tolk.contains "(1 << 256)")
    "wideLiteral must not emit unrepresentable (1 << 256)"
  IO.println "  ✓ UInt256 body literal 2^128 keeps full decimal"

/-- UInt256 shl/shr stay fail closed (int257 can hold the value; 64-count
    shift would drop high bits). -/
private unsafe def testUint256ShiftFc
    (session : Language.Loader.ParserSession) : IO Unit := do
  let srcShl := wrapProgram "Wide256Shl" <|
    "  state s : UInt256\n\n" ++
    "  init(x : UInt256) do\n" ++
    "    s := x\n\n" ++
    "  entry go(d : UInt32) : UInt256 do\n" ++
    "    s := s << d\n" ++
    "    return s\n\n" ++
    "  view peek() : UInt256 do\n" ++
    "    return s\n"
  let compiledShl ← compileSource session srcShl "Examples.Wide256Shl" "<ton-u256-shl>"
  match planTon compiledShl with
  | .error (.planInvariant .ton msg) =>
      expect (msg.contains "shift" || msg.contains "multiword")
        s!"UInt256 shl FC must cite shift/multiword, got: {msg}"
  | .error e => throw <| IO.userError s!"UInt256 shl: unexpected {e.render}"
  | .ok _ => throw <| IO.userError "UInt256 shl: expected FC, got ok"
  let srcShr := wrapProgram "Wide256Shr" <|
    "  state s : UInt256\n\n" ++
    "  init(x : UInt256) do\n" ++
    "    s := x\n\n" ++
    "  entry go(d : UInt32) : UInt256 do\n" ++
    "    s := s >> d\n" ++
    "    return s\n\n" ++
    "  view peek() : UInt256 do\n" ++
    "    return s\n"
  let compiledShr ← compileSource session srcShr "Examples.Wide256Shr" "<ton-u256-shr>"
  match planTon compiledShr with
  | .error (.planInvariant .ton msg) =>
      expect (msg.contains "shift" || msg.contains "multiword")
        s!"UInt256 shr FC must cite shift/multiword, got: {msg}"
  | .error e => throw <| IO.userError s!"UInt256 shr: unexpected {e.render}"
  | .ok _ => throw <| IO.userError "UInt256 shr: expected FC, got ok"
  IO.println "  ✓ UInt256 shl/shr stay fail closed"

/-- Array/Map/Option of UInt256 stay fail closed (scalar UInt256 only). -/
private unsafe def testUint256ContainerFc
    (session : Language.Loader.ParserSession) : IO Unit := do
  let srcArr := wrapProgram "ArrU256" <|
    "  state slots : Array UInt256 2\n\n" ++
    "  init() do\n" ++
    "    slots[0] := 0\n" ++
    "    slots[1] := 0\n\n" ++
    "  entry set0(v : UInt64) : UInt64 do\n" ++
    "    slots[0] := 0\n" ++
    "    return v\n"
  let compiledArr ← compileSource session srcArr "Examples.ArrU256" "<ton-arr-u256>"
  match planTon compiledArr with
  | .error (.planInvariant .ton msg) =>
      expect (msg.contains "Array state element must be UInt64")
        s!"ArrU256 FC must cite Array UInt64 element, got: {msg}"
  | .error e => throw <| IO.userError s!"ArrU256: unexpected {e.render}"
  | .ok _ => throw <| IO.userError "ArrU256: expected FC, got ok"
  let srcMap := wrapProgram "MapU256" <|
    "  state m : Map UInt64 UInt256\n\n" ++
    "  init() do\n" ++
    "    m := Map.empty()\n\n" ++
    "  entry put(k : UInt64, v : UInt64) : UInt64 do\n" ++
    "    return v\n"
  let compiledMap ← compileSource session srcMap "Examples.MapU256" "<ton-map-u256>"
  match planTon compiledMap with
  | .error (.planInvariant .ton msg) =>
      expect (msg.contains "Map state admits only Map UInt64 UInt64")
        s!"MapU256 FC must cite Map UInt64 UInt64, got: {msg}"
  | .error e => throw <| IO.userError s!"MapU256: unexpected {e.render}"
  | .ok _ => throw <| IO.userError "MapU256: expected FC, got ok"
  let srcOpt := wrapProgram "OptU256" <|
    "  state o : Option UInt256\n\n" ++
    "  init() do\n" ++
    "    o := Option.none()\n\n" ++
    "  view get() : UInt64 do\n" ++
    "    return 0\n"
  let compiledOpt ← compileSource session srcOpt "Examples.OptU256" "<ton-opt-u256>"
  match planTon compiledOpt with
  | .error (.planInvariant .ton msg) =>
      expect (msg.contains "Option state 'o' requires UInt64 payload")
        s!"OptU256 FC must cite Option UInt64 payload, got: {msg}"
  | .error e => throw <| IO.userError s!"OptU256: unexpected {e.render}"
  | .ok _ => throw <| IO.userError "OptU256: expected FC, got ok"
  IO.println "  ✓ Array/Map/Option of UInt256 stay fail closed"

/-- UInt256 bitwise stays fail closed (same class as shift >64). -/
private unsafe def testUint256BitwiseFc
    (session : Language.Loader.ParserSession) : IO Unit := do
  let srcAnd := wrapProgram "Wide256And" <|
    "  state s : UInt256\n\n" ++
    "  init(x : UInt256) do\n" ++
    "    s := x\n\n" ++
    "  entry go(d : UInt256) : UInt256 do\n" ++
    "    s := s & d\n" ++
    "    return s\n\n" ++
    "  view peek() : UInt256 do\n" ++
    "    return s\n"
  let compiledAnd ← compileSource session srcAnd "Examples.Wide256And" "<ton-u256-and>"
  match planTon compiledAnd with
  | .error (.planInvariant .ton msg) =>
      expect (msg.contains "bitwise" || msg.contains "multiword")
        s!"UInt256 bitAnd FC must cite bitwise/multiword, got: {msg}"
  | .error e => throw <| IO.userError s!"UInt256 bitAnd: unexpected {e.render}"
  | .ok _ => throw <| IO.userError "UInt256 bitAnd: expected FC, got ok"
  let srcNot := wrapProgram "Wide256Not" <|
    "  state s : UInt256\n\n" ++
    "  init(x : UInt256) do\n" ++
    "    s := x\n\n" ++
    "  entry go() : UInt256 do\n" ++
    "    s := ~s\n" ++
    "    return s\n\n" ++
    "  view peek() : UInt256 do\n" ++
    "    return s\n"
  let compiledNot ← compileSource session srcNot "Examples.Wide256Not" "<ton-u256-not>"
  match planTon compiledNot with
  | .error (.planInvariant .ton msg) =>
      expect (msg.contains "bitwise" || msg.contains "multiword" ||
          msg.contains "bitNot")
        s!"UInt256 bitNot FC must cite bitwise/multiword, got: {msg}"
  | .error e => throw <| IO.userError s!"UInt256 bitNot: unexpected {e.render}"
  | .ok _ => throw <| IO.userError "UInt256 bitNot: expected FC, got ok"
  IO.println "  ✓ UInt256 bitwise stay fail closed"

/-- BL-14: Int128/256 stay fail closed. Scalar UInt256 is admitted separately. -/
private unsafe def testMultiWidthFc
    (session : Language.Loader.ParserSession) : IO Unit := do
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
  -- Int256 stays fail closed (same signed-wide class as Int128).
  let srcI256 := wrapProgram "WideI256" <|
    "  state s : Int256\n\n" ++
    "  init(x : Int256) do\n" ++
    "    s := x\n\n" ++
    "  entry go(d : Int256) : Int256 do\n" ++
    "    s := s + d\n" ++
    "    return s\n\n" ++
    "  view peek() : Int256 do\n" ++
    "    return s\n"
  match ← (do
      try
        let c ← compileSource session srcI256 "Examples.WideI256" "<ton-i256-fc>"
        pure (some c)
      catch _ => pure none) with
  | none => pure ()
  | some c =>
      match planTon c with
      | .error (.planInvariant .ton msg) =>
          expect (msg.contains "Int256" || msg.contains "256" ||
              msg.contains "fail closed" || msg.contains "integer")
            s!"Int256 FC message must cite width, got: {msg}"
      | .error e => throw <| IO.userError s!"Int256: unexpected {e.render}"
      | .ok _ => throw <| IO.userError "Int256: expected FC, got ok"
  IO.println "  ✓ Int128 + Int256 fail closed"

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
  -- Map UInt64 UInt64 view return is admitted as 24-leaf B-RET-MAP
  -- (see testMapReturn). This boundary suite only pins the compile/plan
  -- path so a later FC regression cannot hide behind an earlier throw.
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
  | none => throw <| IO.userError "MapRet: Map UInt64 UInt64 view must compile"
  | some c =>
      match planTon c with
      | .ok plan =>
          let getMap ← findMethod plan "getMap"
          match getMap.resultKind with
          | .aggregate leaves =>
              expect (leaves.size == 24)
                s!"MapRet must have 24 leaves, got {leaves.size}"
          | other =>
              throw <| IO.userError
                s!"MapRet resultKind must be .aggregate, got {repr other}"
      | .error e =>
          throw <| IO.userError
            s!"MapRet: Map UInt64 UInt64 view must Plan, got {e.render}"
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

/-- L4: Option UInt64 param flattens to 2 read-only leaves (`o_tag`/`o_p0`). -/
unsafe def testOptionParam : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let optParamSource := wrapProgram "OptParam" <|
    "  state pad : UInt64\n\n" ++
    "  init(i : UInt64) do\n" ++
    "    pad := i\n\n" ++
    "  entry take(o : Option UInt64) : UInt64 do\n" ++
    "    return pad\n"
  let optCompiled ← compileSource session optParamSource "Examples.OptParam"
    "<ton-opt-param>"
  let optPlan ← liftResult <| planTon optCompiled
  let some take := optPlan.entries.find? (·.name == "take") |
    throw <| IO.userError "OptParam missing take"
  expect (take.params.map (·.name) == #["o_tag", "o_p0"])
    s!"OptParam must flatten to o_tag/o_p0, got {take.params.map (·.name)}"
  IO.println "  ✓ Option UInt64 param flattens to o_tag/o_p0"

unsafe def testArrayParam : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let arrParamSource := wrapProgram "ArrParam" <|
    "  state pad : UInt64\n\n" ++
    "  init(i : UInt64) do\n" ++
    "    pad := i\n\n" ++
    "  entry take(a : Array UInt64 2) : UInt64 do\n" ++
    "    return pad\n"
  let arrCompiled ← compileSource session arrParamSource "Examples.ArrParam"
    "<ton-arr-param>"
  let arrPlan ← liftResult <| planTon arrCompiled
  let some take := arrPlan.entries.find? (·.name == "take") |
    throw <| IO.userError "ArrParam missing take"
  expect (take.params.map (·.name) == #["a_0", "a_1"])
    s!"ArrParam must flatten to a_0/a_1, got {take.params.map (·.name)}"
  IO.println "  ✓ Array UInt64 2 param flattens to a_0/a_1"

unsafe def testArrayInt64Return : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source := wrapProgram "ArrInt64RetTon" <|
    "  state slots : Array Int64 2\n\n" ++
    "  init() do\n" ++
    "    slots[0] := 0\n" ++
    "    slots[1] := 0\n\n" ++
    "  view get() : Array Int64 2 do\n" ++
    "    return slots\n"
  let compiled ← compileSource session source "Examples.ArrInt64RetTon"
    "<ton-arr-int64-ret>"
  let plan ← liftResult <| planTon compiled
  let get ← findMethod plan "get"
  expect (get.mode == .view) "ArrInt64Ret get must be view"
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
  IO.println "  ✓ Array Int64 2 view return 2-leaf int64"

unsafe def testOptionInt64Return : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source := wrapProgram "OptInt64RetTon" <|
    "  state slot : Option Int64\n\n" ++
    "  init() do\n" ++
    "    slot := Option.none()\n\n" ++
    "  view get() : Option Int64 do\n" ++
    "    return slot\n"
  let compiled ← compileSource session source "Examples.OptInt64RetTon"
    "<ton-opt-int64-ret>"
  let plan ← liftResult <| planTon compiled
  let get ← findMethod plan "get"
  expect (get.mode == .view) "OptInt64Ret get must be view"
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

unsafe def testMapReturn : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source := wrapProgram "MapRetTon" <|
    "  state m : Map UInt64 UInt64\n\n" ++
    "  init() do\n" ++
    "    m := Map.empty()\n\n" ++
    "  view dump() : Map UInt64 UInt64 do\n" ++
    "    return m\n"
  let compiled ← compileSource session source "Examples.MapRetTon"
    "<ton-map-ret>"
  let plan ← liftResult <| planTon compiled
  let dump ← findMethod plan "dump"
  expect (dump.mode == .view) "MapRet dump must be view"
  match dump.resultKind with
  | .aggregate leaves =>
      expect (leaves.size == 24)
        s!"MapRet dump must have 24 leaves, got {leaves.size}"
      expect (leaves.all (fun l => !l.isInt && l.byteWidth == 8))
        "MapRet leaves must be unsigned 8-byte words"
  | other =>
      throw <| IO.userError
        s!"MapRet dump resultKind must be .aggregate, got {repr other}"
  liftResult <| validatePlan plan
  IO.println "  ✓ Map UInt64 UInt64 view return 24-leaf B-RET-MAP"

unsafe def testMapInt64Return : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source := wrapProgram "MapInt64RetTon" <|
    "  state m : Map UInt64 Int64\n\n" ++
    "  init() do\n" ++
    "    m := Map.empty()\n\n" ++
    "  view dump() : Map UInt64 Int64 do\n" ++
    "    return m\n"
  let compiled ← compileSource session source "Examples.MapInt64RetTon"
    "<ton-map-int64-ret>"
  let plan ← liftResult <| planTon compiled
  let dump ← findMethod plan "dump"
  expect (dump.mode == .view) "MapInt64Ret dump must be view"
  match dump.resultKind with
  | .aggregate leaves =>
      expect (leaves.size == 24)
        s!"MapInt64Ret dump must have 24 leaves, got {leaves.size}"
      expect ((List.range 24).all (fun i =>
          leaves[i]!.isInt == (i % 3 == 2)))
        "MapInt64Ret val slots must be isInt"
  | other =>
      throw <| IO.userError
        s!"MapInt64Ret dump resultKind must be .aggregate, got {repr other}"
  liftResult <| validatePlan plan
  IO.println "  ✓ Map UInt64 Int64 view return 24-leaf val-only isInt"

unsafe def testMapParam : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source := wrapProgram "MapParamTon" <|
    "  state pad : UInt64\n\n" ++
    "  init() do\n" ++
    "    pad := 0\n\n" ++
    "  entry put(m : Map UInt64 UInt64) : UInt64 do\n" ++
    "    return pad\n"
  let compiled ← compileSource session source "Examples.MapParamTon"
    "<ton-map-param>"
  let plan ← liftResult <| planTon compiled
  let put ← findMethod plan "put"
  let expected := (List.range 24).toArray.map (fun i => s!"m_{i}")
  expect (put.params.map (·.name) == expected)
    s!"MapParam must flatten to 24 occ/key/val leaves, got {put.params.map (·.name)}"
  liftResult <| validatePlan plan
  IO.println "  ✓ MapParam 24-leaf occ/key/val flatten"

unsafe def testBytesReturn : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source := wrapProgram "BytesRetTon" <|
    "  state b : Bytes 2\n\n" ++
    "  init() do\n" ++
    "    b[0] := 0\n" ++
    "    b[1] := 0\n\n" ++
    "  view get() : Bytes 2 do\n" ++
    "    return b\n"
  let compiled ← compileSource session source "Examples.BytesRetTon"
    "<ton-bytes-ret>"
  let plan ← liftResult <| planTon compiled
  let get ← findMethod plan "get"
  expect (get.mode == .view) "BytesRet get must be view"
  match get.resultKind with
  | .aggregate leaves =>
      expect (leaves.size == 2)
        s!"BytesRet must have 2 leaves, got {leaves.size}"
      expect (leaves.all (fun l => !l.isInt && l.byteWidth == 1))
        "BytesRet leaves must be uint8 cells"
  | other =>
      throw <| IO.userError
        s!"BytesRet get resultKind must be .aggregate, got {repr other}"
  IO.println "  ✓ Bytes 2 view return 2×uint8 cells"

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

/-- TON-OPT-INT: Option Int64 state = unsigned tag + signed 8-byte payload
    (same flatten as Option UInt64; not a UInt64 alias and not CosmWasm
    Regions). peek match returns Int64 — anonymous Option Int64 return stays
    fail closed. -/
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
    "<ton-option-int64>"
  let plan ← liftResult <| planTon compiled
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
  let noneAtomic (body : Array Statement) : Bool :=
    body.any fun s =>
      match s with
      | .storeAtomic leaves =>
          leaves.size == 2 &&
            leaves[0]!.byteWidth == 8 && leaves[1]!.byteWidth == 8 &&
            leaves[0]!.value == .literal 0 && leaves[1]!.value == .literal 0 &&
            leaves[0]!.fieldIndex == plan.storage.fields[0]!.sourceId &&
            leaves[1]!.fieldIndex == plan.storage.fields[1]!.sourceId
      | _ => false
  expect (noneAtomic plan.initializer.body)
    "OptInt64 init Option.none must storeAtomic 2-leaf zeros"
  let some set := plan.entries.find? (·.name == "set") |
    throw <| IO.userError "OptInt64 missing set"
  expect (set.resultKind == MethodResultKind.int64) "OptInt64 set result Int64"
  let setAtomic := set.body.any fun s =>
    match s with
    | .storeAtomic leaves =>
        leaves.size == 2 &&
          leaves[0]!.byteWidth == 8 && leaves[1]!.byteWidth == 8 &&
          leaves[0]!.value == .literal 1 &&
          match leaves[1]!.value with
          | .param _ => true
          | _ => false
    | _ => false
  expect setAtomic "OptInt64 set some(v) must storeAtomic tag=1 + Int64 param"
  let some clear := plan.entries.find? (·.name == "clear") |
    throw <| IO.userError "OptInt64 missing clear"
  expect (noneAtomic clear.body)
    "OptInt64 clear Option.none must storeAtomic 2-leaf zeros"
  let some peek := plan.entries.find? (·.name == "peek") |
    throw <| IO.userError "OptInt64 missing peek"
  expect (peek.mode == .view && peek.resultKind == MethodResultKind.int64)
    "OptInt64 peek must be view Int64 (not Option Int64 return)"
  match validatePlan plan with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"OptInt64 plan must validate: {e.render}"
  let files ← liftResult <| filesTon compiled
  let tolk ← findFile files "OptInt64.tolk"
  expect (tolk.contains "slot_tag: uint64") "OptInt64 Tolk slot_tag: uint64"
  expect (tolk.contains "slot_p0: int64") "OptInt64 Tolk slot_p0: int64"
  expect (!tolk.contains "slot_p0: uint64")
    "OptInt64 Tolk must not alias slot_p0 as uint64"
  expect (tolk.contains "body.loadInt(64)") "OptInt64 param loadInt(64)"
  let abi ← findFile files "OptInt64.ton-abi.json"
  expect (abi.contains "{\"name\":\"slot_tag\",\"type\":\"uint64\"}")
    s!"OptInt64 ABI tag must stay uint64, got: {abi}"
  expect (abi.contains "{\"name\":\"slot_p0\",\"type\":\"int64\"}")
    s!"OptInt64 ABI p0 must be int64 (not a UInt64 alias), got: {abi}"
  expect (abi.contains "\"type\":\"int64\"") "OptInt64 ABI JSON type int64"
  expect (abi.contains "\"returns\":\"int64\"") "OptInt64 ABI returns int64"
  IO.println "  ✓ Option Int64 state tag+signed int64 cell Plan/IR/Tolk/ABI pin"

/-- Option Int8 stays fail closed on the historical payload needle
    (`requires UInt64 payload` is a contains-match). Anonymous
    `Option Int64` return stays fail closed on the existing UInt64-payload
    return needle. Option UInt128  state is admitted separately. -/
private unsafe def testOptionInt64ElementFc
    (session : Language.Loader.ParserSession) : IO Unit := do
  let optI8 := wrapProgram "OptI8Ton" <|
    "  state o : Option Int8\n\n" ++
    "  init() do\n" ++
    "    o := Option.none()\n\n" ++
    "  view peek() : UInt64 do\n" ++
    "    return 0\n"
  let optI8Compiled ← compileSource session optI8 "Examples.OptI8Ton" "<ton-opt-i8-el>"
  expectPlanErrorContaining "OptI8" "requires UInt64 payload"
    (planTon optI8Compiled)
  IO.println "  ✓ Option Int8 stay fail closed"

/-- TON-OPT-U128: Option UInt128 state = unsigned tag uint64 + one
    unsigned uint128 payload cell (same 2-leaf flatten as Option
    UInt64/Int64; not CosmWasm 2-limb Regions and not two UInt64
    leaves). peek match returns UInt128 — anonymous Option UInt128
    return stays fail closed. Cell budget 64+64+128=256 ≤ 1023. -/
private unsafe def testOptionUInt128State
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrapProgram "OptU128" <|
    "  state slot : Option UInt128\n\n" ++
    "  init() do\n" ++
    "    slot := Option.none()\n\n" ++
    "  entry set(v : UInt128) : UInt128 do\n" ++
    "    slot := Option.some(v)\n" ++
    "    return v\n\n" ++
    "  entry clear() : UInt128 do\n" ++
    "    slot := Option.none()\n" ++
    "    return 0\n\n" ++
    "  view peek() : UInt128 do\n" ++
    "    match slot with\n" ++
    "    | Option.some(x) => do\n" ++
    "      return x\n" ++
    "    | _ => do\n" ++
    "      return 0\n"
  let compiled ← compileSource session source "Examples.OptU128"
    "<ton-option-uint128>"
  let plan ← liftResult <| planTon compiled
  expect (plan.storage.fields.size == 2)
    s!"OptU128: Option UInt128 must flatten to tag+payload (2), got {plan.storage.fields.size}"
  expect (plan.storage.fields.map (·.name) == #["slot_tag", "slot_p0"])
    s!"OptU128: leaf names must be slot_tag/slot_p0, got {plan.storage.fields.map (·.name)}"
  expect (plan.storage.fields[0]!.byteWidth == 8) "OptU128 tag byteWidth=8"
  expect (plan.storage.fields[1]!.byteWidth == 16) "OptU128 p0 byteWidth=16"
  expect (!plan.storage.fields[0]!.isInt) "OptU128 tag stays unsigned"
  expect (!plan.storage.fields[1]!.isInt) "OptU128 p0 is unsigned UInt128"
  expect (layoutFieldTypeSuffix
      plan.storage.fields[0]!.byteWidth plan.storage.fields[0]!.isInt == "u64-le")
    "OptU128 tag ABI suffix is u64-le"
  expect (layoutFieldTypeSuffix
      plan.storage.fields[1]!.byteWidth plan.storage.fields[1]!.isInt == "u128-le")
    "OptU128 p0 ABI suffix is u128-le (not u64-le / not 2-limb)"
  let noneAtomic (body : Array Statement) : Bool :=
    body.any fun s =>
      match s with
      | .storeAtomic leaves =>
          leaves.size == 2 &&
            leaves[0]!.byteWidth == 8 && leaves[1]!.byteWidth == 16 &&
            leaves[0]!.value == .literal 0 && leaves[1]!.value == .literal 0 &&
            leaves[0]!.fieldIndex == plan.storage.fields[0]!.sourceId &&
            leaves[1]!.fieldIndex == plan.storage.fields[1]!.sourceId
      | _ => false
  expect (noneAtomic plan.initializer.body)
    "OptU128 init Option.none must storeAtomic tag u64 + payload u128 zeros"
  let some set := plan.entries.find? (·.name == "set") |
    throw <| IO.userError "OptU128 missing set"
  expect (set.resultKind == MethodResultKind.uint128) "OptU128 set result UInt128"
  let setAtomic := set.body.any fun s =>
    match s with
    | .storeAtomic leaves =>
        leaves.size == 2 &&
          leaves[0]!.byteWidth == 8 && leaves[1]!.byteWidth == 16 &&
          leaves[0]!.value == .literal 1 &&
          match leaves[1]!.value with
          | .param _ => true
          | .narrowParam 128 _ => true
          | _ => false
    | _ => false
  expect setAtomic "OptU128 set some(v) must storeAtomic tag=1 + UInt128 param"
  let some clear := plan.entries.find? (·.name == "clear") |
    throw <| IO.userError "OptU128 missing clear"
  expect (noneAtomic clear.body)
    "OptU128 clear Option.none must storeAtomic 2-leaf zeros"
  let some peek := plan.entries.find? (·.name == "peek") |
    throw <| IO.userError "OptU128 missing peek"
  expect (peek.mode == .view && peek.resultKind == MethodResultKind.uint128)
    "OptU128 peek must be view UInt128 (not Option UInt128 return)"
  match validatePlan plan with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"OptU128 plan must validate: {e.render}"
  let files ← liftResult <| filesTon compiled
  let tolk ← findFile files "OptU128.tolk"
  expect (tolk.contains "slot_tag: uint64") "OptU128 Tolk slot_tag: uint64"
  expect (tolk.contains "slot_p0: uint128") "OptU128 Tolk slot_p0: uint128"
  expect (!tolk.contains "slot_p0: uint64")
    "OptU128 Tolk must not alias slot_p0 as uint64"
  expect (!tolk.contains "slot_p0_lo" && !tolk.contains "slot_p0_hi" &&
      !tolk.contains "slot_p0_l0" && !tolk.contains "slot_p0_l1")
    "OptU128 Tolk must not emit CosmWasm 2-limb names"
  expect (tolk.contains "body.loadUint(128)") "OptU128 param loadUint(128)"
  expect (tolk.contains "(1 << 128)") "OptU128 UInt128 range guard"
  let abi ← findFile files "OptU128.ton-abi.json"
  expect (abi.contains "{\"name\":\"slot_tag\",\"type\":\"uint64\"}")
    s!"OptU128 ABI tag must stay uint64, got: {abi}"
  expect (abi.contains "{\"name\":\"slot_p0\",\"type\":\"uint128\"}")
    s!"OptU128 ABI p0 must be uint128 (not a UInt64 alias), got: {abi}"
  expect (abi.contains "\"type\":\"uint128\"") "OptU128 ABI JSON type uint128"
  expect (abi.contains "\"returns\":\"uint128\"") "OptU128 ABI returns uint128"
  IO.println "  ✓ Option UInt128 state tag+uint128 cell Plan/IR/Tolk/ABI pin"

/-- Anonymous Option UInt128 view return stays UInt64-only after state
    started admitting a UInt128 payload. -/
private unsafe def testOptionUInt128ReturnFc
    (session : Language.Loader.ParserSession) : IO Unit := do
  let src := wrapProgram "OptU128Ret" <|
    "  state slot : Option UInt128\n\n" ++
    "  init() do\n" ++
    "    slot := Option.none()\n\n" ++
    "  view get() : Option UInt128 do\n" ++
    "    return slot\n"
  let compiled ← compileSource session src "Examples.OptU128Ret"
    "<ton-opt-u128-ret>"
  expectPlanErrorContaining "OptU128Ret"
    "anonymous Option return requires UInt64 or Int64 payload"
    (planTon compiled)
  IO.println "  ✓ Option UInt128 return stays fail closed"

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
  -- (d) context.caller stays fail closed. TON Principal storage is admitted
  -- (T12), so rejection is at the ContextRead/caller arm (not type-closure).
  -- Needs a state leaf so profile state-count gates do not mask that arm.
  let callerSrc := wrapProgram "CallerBox" <|
    "  state pad : UInt64\n" ++
    "  init() do\n" ++
    "    pad := 0\n" ++
    "  entry who() : UInt64 do\n" ++
    "    let c : Principal := context.caller\n" ++
    "    return 0\n" ++
    "  view get() : UInt64 do\n" ++
    "    return pad\n"
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
  -- `proof-forge.context.self.v1`) is Principal. TON Principal storage is
  -- admitted (T12), so rejection is at the ContextRead/self arm. Needs a
  -- state leaf so profile state-count gates do not mask that arm.
  let selfSrc := wrapProgram "SelfBox" <|
    "  state pad : UInt64\n" ++
    "  init() do\n" ++
    "    pad := 0\n" ++
    "  entry who() : UInt64 do\n" ++
    "    let s : Principal := context.contractId\n" ++
    "    return 0\n" ++
    "  view get() : UInt64 do\n" ++
    "    return pad\n"
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

/-- T3: scalar Op.Constant inlines as the existing literal envelope. -/
private unsafe def testScalarConstInline
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrapProgram "ConstBox" <|
    "  const ANSWER : UInt64 := 42\n\n" ++
    "  state stored : UInt64\n\n" ++
    "  init() do\n" ++
    "    stored := 0\n\n" ++
    "  entry answer() : UInt64 do\n" ++
    "    stored := stored + ANSWER\n" ++
    "    return stored\n"
  let compiled ← compileSource session source "Examples.ConstBox" "<ton-const-box>"
  let plan ← liftResult (planTon compiled)
  expect (plan.storage.fields.size == 1)
    s!"ConstBox must keep a single UInt64 field, got {plan.storage.fields.size}"
  let strSource := wrapProgram "ConstStr" <|
    "  const GREETING : String := \"hi\"\n\n" ++
    "  state count : UInt64\n\n" ++
    "  init() do\n" ++
    "    count := 0\n\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let strCompiled ← compileSource session strSource "Examples.ConstStr" "<ton-const-str>"
  let strPlan ← liftResult (planTon strCompiled)
  expect (strPlan.storage.fields.size == 1)
    s!"ConstStr unused String const must keep a single UInt64 field, got {strPlan.storage.fields.size}"
  IO.println "  ✓ Ton scalar const inline + unused String const table admit ok"

/-- T4: Principal state/params flatten to 9 UInt64 identity leaves. Return FC. -/
private unsafe def testPrincipalIdentityLeaves
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrapProgram "PrincipalMix" <|
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
  let compiled ← compileSource session source "Examples.PrincipalMix" "<ton-principal>"
  let plan ← liftResult (planTon compiled)
  expect (plan.storage.fields.size == 9)
    s!"Principal state must flatten to 9 leaves, got {plan.storage.fields.size}"
  expect (plan.storage.fields[0]!.name == "owner_len")
    s!"Principal leaf 0 must be owner_len, got {plan.storage.fields[0]!.name}"
  expect (plan.storage.fields[1]!.name == "owner_w0")
    s!"Principal leaf 1 must be owner_w0, got {plan.storage.fields[1]!.name}"
  expect (plan.storage.fields[8]!.name == "owner_w7")
    s!"Principal leaf 8 must be owner_w7, got {plan.storage.fields[8]!.name}"
  let retSource := wrapProgram "PrincipalReturn" <|
    "  state owner : Principal\n\n" ++
    "  init(initial : Principal) do\n" ++
    "    owner := initial\n\n" ++
    "  view getOwner() : Principal do\n" ++
    "    return owner\n"
  let compiledRet ← compileSource session retSource "Examples.PrincipalReturn" "<ton-principal-ret>"
  let planRet ← liftResult (planTon compiledRet)
  let getOwner ← findMethod planRet "getOwner"
  expect (getOwner.mode == .view) "PrincipalReturn getOwner must be view"
  match getOwner.resultKind with
  | .aggregate leaves =>
      expect (leaves.size == 9)
        s!"PrincipalReturn aggregate return must have 9 leaves, got {leaves.size}"
      expect (leaves.all (fun l => !l.isInt && l.byteWidth == 8))
        "PrincipalReturn leaves must be unsigned 8-byte identity words"
  | other =>
      throw <| IO.userError
        s!"PrincipalReturn getOwner resultKind must be .aggregate, got {repr other}"
  IO.println "  ✓ Ton Principal 9-leaf identity + view return"

unsafe def testPrincipalReturn : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source := wrapProgram "PrinRetTon" <|
    "  state owner : Principal\n\n" ++
    "  init(initial : Principal) do\n" ++
    "    owner := initial\n\n" ++
    "  view getOwner() : Principal do\n" ++
    "    return owner\n"
  let compiled ← compileSource session source "Examples.PrinRetTon" "<ton-prin-ret-focus>"
  let plan ← liftResult (planTon compiled)
  let getOwner ← findMethod plan "getOwner"
  expect (getOwner.mode == .view) "PrinRetTon getOwner must be view"
  match getOwner.resultKind with
  | .aggregate leaves =>
      expect (leaves.size == 9)
        s!"PrinRetTon must have 9 leaves, got {leaves.size}"
      expect (leaves.all (fun l => !l.isInt && l.byteWidth == 8))
        "PrinRetTon leaves must be unsigned 8-byte identity words"
  | other =>
      throw <| IO.userError
        s!"PrinRetTon getOwner resultKind must be .aggregate, got {repr other}"
  IO.println "  ✓ Principal view return 9-leaf identity"

unsafe def testStringReturn : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source := wrapProgram "StrRetTon" <|
    "  state label : String\n\n" ++
    "  init(initial : String) do\n" ++
    "    label := initial\n\n" ++
    "  view getLabel() : String do\n" ++
    "    return label\n"
  let compiled ← compileSource session source "Examples.StrRetTon" "<ton-str-ret-focus>"
  let plan ← liftResult (planTon compiled)
  let getLabel ← findMethod plan "getLabel"
  expect (getLabel.mode == .view) "StrRetTon getLabel must be view"
  match getLabel.resultKind with
  | .aggregate leaves =>
      expect (leaves.size == 9)
        s!"StrRetTon must have 9 leaves, got {leaves.size}"
      expect (leaves.all (fun l => !l.isInt && l.byteWidth == 8))
        "StrRetTon leaves must be unsigned 8-byte identity words"
  | other =>
      throw <| IO.userError
        s!"StrRetTon getLabel resultKind must be .aggregate, got {repr other}"
  let entrySrc := wrapProgram "StrEntryTon" <|
    "  state label : String\n\n" ++
    "  init(initial : String) do\n" ++
    "    label := initial\n\n" ++
    "  entry setLabel(next : String) : String do\n" ++
    "    label := next\n" ++
    "    return label\n"
  let entryCompiled ← compileSource session entrySrc "Examples.StrEntryTon"
    "<ton-str-entry-focus>"
  expectPlanErrorContaining "StrEntryTon" "cannot return multi-leaf aggregate"
    (planTon entryCompiled)
  IO.println "  ✓ String view return 9-leaf identity; TON entry String stays FC"

unsafe def testConstStr : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source := wrapProgram "GreetingBox" <|
    "  const GREETING : String := \"hi\"\n\n" ++
    "  state label : String\n\n" ++
    "  init() do\n" ++
    "    label := GREETING\n\n" ++
    "  view getLabel() : String do\n" ++
    "    return label\n"
  let compiled ← compileSource session source "Examples.GreetingBox" "<ton-const-str-focus>"
  let plan ← liftResult (planTon compiled)
  let getLabel ← findMethod plan "getLabel"
  expect (getLabel.mode == .view) "GreetingBox getLabel must be view"
  match getLabel.resultKind with
  | .aggregate leaves =>
      expect (leaves.size == 9)
        s!"GreetingBox must have 9 leaves, got {leaves.size}"
  | other =>
      throw <| IO.userError
        s!"GreetingBox getLabel resultKind must be .aggregate, got {repr other}"
  IO.println "  ✓ String const 9-leaf inline"

unsafe def testStrMatch : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source := wrapProgram "StrMatch" <|
    "  state pad : UInt64\n\n" ++
    "  init() do\n" ++
    "    pad := 0\n\n" ++
    "  entry classify(s : String) : UInt64 do\n" ++
    "    match s with\n" ++
    "    | \"a\" => do\n" ++
    "      return 1\n" ++
    "    | _ => do\n" ++
    "      return 0\n"
  let compiled ← compileSource session source "Examples.StrMatch" "<ton-str-match>"
  let plan ← liftResult (planTon compiled)
  let classify ← findMethod plan "classify"
  expect (classify.mode != .view) "StrMatch classify must be an entry"
  IO.println "  ✓ String match desugars to nested ifThenElse"

unsafe def run : IO Unit := do
  IO.println "TonPlanV1"
  let session ← Tests.Language.ParserSession.shared
  testStateCellPlan session
  testStateCellIRAndTolk session
  testMultiField session
  testCallSyncFc session
  testResultBearingExternalCallFailClosed
  testCryptoSha256Admitted session
  testCryptoSha256BytesAdmitted session
  testSchedulePlanAndTolk session
  testNarrowUInt8 session
  testNarrowUInt16UInt32 session
  testNarrowInt8 session
  testNarrowInt16Int32 session
  testSignedContainerFc session
  testArrayInt64State session
  testArrayInt64x24Layout session
  testArrayInt64ElementFc session
  testArrayUInt128State session
  testArrayUInt128CellBudget session
  testArrayUInt128SiblingCellBudget session
  testArrayUInt128ReturnFc session
  testMapInt64State session
  testMapInt64ElementFc session
  testMapReturn
  testMapInt64Return
  testMapParam
  testUint128Abi session
  testUint128WideLiteral session
  testUint128ShiftFc session
  testUint256Abi session
  testUint256WideLiteral session
  testUint256ShiftFc session
  testUint256ContainerFc session
  testUint256BitwiseFc session
  testMultiWidthFc session
  testRegistryDispatch session
  testNamedStructReturn session
  testNamedEnumReturn session
  testAnonymousArrayReturn session
  testAnonymousOptionReturn session
  testOptionState session
  testOptionInt64State session
  testOptionInt64ElementFc session
  testOptionUInt128State session
  testOptionUInt128ReturnFc session
  testAggregateFailClosed session
  testOptionParam
  testArrayParam
  testContextReadUnixTime session
  testEnvReadNativeStayFailClosed session
  testUnknownProfileFailClosed
  testScalarConstInline session
  testPrincipalIdentityLeaves session
  IO.println "TonPlanV1: all checks passed"

end Tests.Materialization.TonPlanV1
