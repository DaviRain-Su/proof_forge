/-
  Soroban S0 target leaf tests (ADR-0044): Plan/IR/emitter over retained
  SemanticProgramV1. Uses planFromCompiledSemanticV1 / buildFromCompiledSemanticV1.
  SOR-1a: product Finalize honesty + unknown-profile fail-closed (no Wasm
  profile id; S0 `{name}.rs` is not a cargo package).
-/
import ProofForgeV2
import ProofForgeV2.Targets.Soroban
import Tests.Language.ParserSession
import Tests.Compiler.ValidatedSourceV1Pipeline

namespace Tests.Materialization.SorobanPlanV1

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Targets

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def liftResult (result : CompileResult α) : IO α :=
  match result with
  | .ok value => pure value
  | .error error => throw <| IO.userError error.render

private def planSoroban (compiled : CompiledSemanticV1) : CompileResult Targets.Soroban.Plan :=
  Targets.Soroban.planFromCompiledSemanticV1 compiled

private def buildSoroban (compiled : CompiledSemanticV1) :
    CompileResult (Array OutputFile) :=
  Targets.Soroban.buildFromCompiledSemanticV1 compiled

/-- StateCell: plan shape + key Rust source fragments. -/
unsafe def testStateCellSorobanSource : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program StateCell where\n" ++
    "  state count : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry increment(delta : UInt64) : UInt64 do\n" ++
    "    count := count + delta\n" ++
    "    return count\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<soroban-state-cell>" "Tests.SorobanStateCell" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planSoroban compiled
  expect (plan.states.map (·.name) == #["count"])
    "StateCell Soroban plan must carry the count state field"
  expect (plan.entries.map (·.name) == #["increment"])
    "StateCell Soroban plan must carry the increment entry"
  expect (plan.views.map (·.name) == #["get"])
    "StateCell Soroban plan must carry the get view"
  expect (!plan.signedNumeric)
    "StateCell stays unsigned UInt64"
  match plan.initializer with
  | some initFn =>
      expect (initFn.params == #["initial"])
        "StateCell init must carry the initial parameter"
      expect (initFn.stores.size == 1)
        "StateCell init must store count"
  | none => throw <| IO.userError "StateCell must have an initializer"
  let some inc := plan.entries[0]? |
    throw <| IO.userError "missing increment entry"
  let overflowOk :=
    match inc.checks[0]? with
    | some ck => inc.checks.size == 1 && ck.kind == .overflow
    | none => false
  expect overflowOk "increment must carry a single overflow check"
  liftResult <| Targets.Soroban.validatePlan plan
  let d1 ← match Targets.Soroban.engineeringSorobanPlanDigestV1 plan with
    | .ok d => pure d
    | .error e => throw <| IO.userError e
  let d2 ← match Targets.Soroban.engineeringSorobanPlanDigestV1 plan with
    | .ok d => pure d
    | .error e => throw <| IO.userError e
  expect (d1 == d2) "Soroban plan digest must be deterministic"
  let files ← liftResult <| buildSoroban compiled
  let some rsFile := files.find? (fun f => f.path == "StateCell.rs") |
    throw <| IO.userError "soroban: missing StateCell.rs"
  expect (rsFile.mediaType == "text/x-rust")
    "StateCell.rs media type must be text/x-rust"
  let rs := rsFile.contents
  expect (rs.contains "#[contract]")
    "Soroban source must declare #[contract]"
  expect (rs.contains "#[contractimpl]")
    "Soroban source must declare #[contractimpl]"
  expect (rs.contains "pub struct StateCell")
    "Soroban source must declare the contract struct"
  expect (rs.contains "symbol_short!(\"count\")")
    "Soroban source must use instance storage key for count"
  expect (rs.contains "let st_count =")
    "Soroban entry must snapshot state into a local before stores"
  expect (rs.contains "st_count.checked_add(delta)")
    "Soroban source must use checked_add on the pre-state local"
  expect (rs.contains "delta: u64")
    "unsigned StateCell params stay u64"
  expect (rs.contains "-> u64")
    "unsigned StateCell results stay u64"
  expect (rs.contains "unwrap_or(0_u64)")
    "unsigned StateCell storage default stays 0_u64"
  expect (!rs.contains "i64")
    "unsigned StateCell must not emit i64"
  expect (!rs.contains "unwrap_or(0_u64).checked_add(delta).expect(\"overflow\") <= ")
    "Soroban must not re-get storage inside overflow predicates"
  expect (rs.contains "ProofForge Soroban S0")
    "Soroban source must carry the S0 honesty header"
  expect (!rs.contains "sol_invoke")
    "Soroban source must not invent Solana CPI"

/-- Homogeneous Int64: signed Rust domain + checked signed arith. -/
unsafe def testInt64CellSorobanSource : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program Int64Cell where\n" ++
    "  state count : Int64\n" ++
    "  init(initial : Int64) do\n" ++
    "    count := initial\n" ++
    "  entry increment(delta : Int64) : Int64 do\n" ++
    "    count := count + delta\n" ++
    "    return count\n" ++
    "  view get() : Int64 do\n" ++
    "    return count\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<soroban-int64-cell>" "Tests.SorobanInt64Cell" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planSoroban compiled
  expect plan.signedNumeric "Int64Cell Plan is signed"
  expect (plan.states.map (·.name) == #["count"])
    "Int64Cell Soroban plan must carry the count state field"
  liftResult <| Targets.Soroban.validatePlan plan
  let files ← liftResult <| buildSoroban compiled
  let some rsFile := files.find? (fun f => f.path == "Int64Cell.rs") |
    throw <| IO.userError "soroban: missing Int64Cell.rs"
  let rs := rsFile.contents
  expect (rs.contains "i64")
    "signed Soroban source must use i64"
  expect (rs.contains "delta: i64")
    "signed Soroban params must be i64"
  expect (rs.contains "-> i64")
    "signed Soroban results must be i64"
  expect (rs.contains "st_count.checked_add(delta)")
    "signed Soroban source must use checked_add"
  expect (rs.contains "unwrap_or(0_i64)")
    "signed Soroban storage default is 0_i64"
  expect (!rs.contains "0_u64")
    "signed program must not use the UInt64 storage default"
  expect (!rs.contains "delta: u64")
    "signed program must not type params as u64"

/-- Mixing Int64 state with a UInt64 view is fail closed. -/
unsafe def testMixedInt64UInt64Fc : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program MixInt64 where\n" ++
    "  state count : Int64\n" ++
    "  init(initial : Int64) do\n" ++
    "    count := initial\n" ++
    "  entry increment(delta : Int64) : Int64 do\n" ++
    "    count := count + delta\n" ++
    "    return count\n" ++
    "  view get() : UInt64 do\n" ++
    "    return 0\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<soroban-mix-int64>" "Tests.SorobanMixInt64" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  match planSoroban compiled with
  | .error (.planInvariant .soroban msg) =>
      expect (msg.contains "mixes")
        s!"mixed Int64/UInt64 must name mixes, got: {msg}"
  | .error e => throw <| IO.userError s!"expected planInvariant .soroban, got {e.render}"
  | .ok _ => throw <| IO.userError "mixed Int64/UInt64 must fail closed at Soroban plan"

/-- Multi-width UInt fails closed. -/
unsafe def testMultiWidthFailClosed : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program Wide where\n" ++
    "  state count : UInt32\n" ++
    "  init() do\n" ++
    "    count := 0\n" ++
    "  entry bump() : UInt32 do\n" ++
    "    count := count + 1\n" ++
    "    return count\n" ++
    "  view get() : UInt32 do\n" ++
    "    return count\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<soroban-wide>" "Tests.SorobanWide" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  match planSoroban compiled with
  | .error e =>
      expect (e.code == "PF-PLAN-INVARIANT")
        s!"multi-width must be planInvariant, got {e.code}"
  | .ok _ => throw <| IO.userError "multi-width UInt32 must fail closed"

/-- Nonempty invariant fails closed. -/
unsafe def testInvariantFailClosed : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program InvCell where\n" ++
    "  state count : UInt64\n" ++
    "  init() do\n" ++
    "    count := 0\n" ++
    "  entry bump() : UInt64 do\n" ++
    "    count := count + 1\n" ++
    "    return count\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n" ++
    "  invariant even : count % 2 == 0\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<soroban-inv>" "Tests.SorobanInv" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  match planSoroban compiled with
  | .error e =>
      expect (e.code == "PF-PLAN-INVARIANT")
        s!"invariant must be planInvariant, got {e.code}"
  | .ok _ => throw <| IO.userError "nonempty invariant must fail closed"

/-- Sync call fails closed (resolve or Plan). -/
unsafe def testCallFailClosed : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program CallCell where\n" ++
    "  state count : UInt64\n" ++
    "  init() do\n" ++
    "    count := 0\n" ++
    "  entry bump(s : UInt64) : UInt64 do\n" ++
    "    call Other.method(s)\n" ++
    "    count := count + 1\n" ++
    "    return count\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<soroban-call>" "Tests.SorobanCall" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  match planSoroban compiled with
  | .error e =>
      expect (e.render.contains "op is outside S0")
        s!"generic call Plan FC must contain 'op is outside S0', got: {e.render}"
  | .ok _ => throw <| IO.userError "sync call must fail closed on Soroban S0"

/-- SYS-S5: Soroban has no sha256/keccak256 host. Exact `pf.crypto.*` stays
    Plan fail closed (no host / precompile / circuit gadget). -/
unsafe def testCryptoSha256StayFailClosed : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let expectPlanFc (label body needle : String)
      (also : String := "") : IO Unit := do
    let source :=
      "import ProofForgeV2\n" ++
      "open ProofForgeV2.Language\n" ++
      s!"program {label} where\n" ++ body
    let parsed ← liftResult (← session.selectProgramV1
      source s!"<soroban-{label}>" s!"Tests.Soroban{label}" none)
    let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
    match planSoroban compiled with
    | .error e =>
        expect (e.render.contains needle)
          s!"{label} Plan FC must contain '{needle}', got: {e.render}"
        unless also.isEmpty do
          expect (e.render.contains also)
            s!"{label} Plan FC must contain '{also}', got: {e.render}"
    | .ok _ =>
        throw <| IO.userError
          s!"{label} must Plan fail closed (no Soroban crypto host)"
  let cryptoBody (qn : String) : String :=
    "  state pad : UInt64\n" ++
      "  init() do\n" ++
      "    pad := 0\n" ++
      "  entry probe() : UInt64 do\n" ++
      "    let w : UInt64 := 0\n" ++
      "    let h : UInt64 := call " ++ qn ++ "(w)\n" ++
      "    return pad\n" ++
      "  view get() : UInt64 do\n" ++
      "    return pad\n"
  expectPlanFc "Sha256Soroban" (cryptoBody "pf.crypto.sha256")
    "has no Soroban host binding"
  expectPlanFc "Keccak256Soroban" (cryptoBody "pf.crypto.keccak256")
    "has no Soroban host binding"
  expectPlanFc "Sha256SorobanHashNoPad" (cryptoBody "pf.crypto.hashNoPad")
    "has no Soroban host binding"
  expectPlanFc "EcdsaRecoverSoroban"
    (cryptoBody "pf.crypto.ecdsaRecoverSecp256k1")
    "has no Soroban host binding" "ecdsaRecoverSecp256k1"

/-- SYS-S4: Soroban has no unixTime/blockHeight/attachedValue/chainId host.
    Named UInt64 ContextRead keys stay Plan fail closed. caller/self are
    Principal and stay on the generic ContextRead envelope (S0 rejects
    Principal at type closure first). -/
unsafe def testContextReadStayFailClosed : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let expectPlanFc (label body needle schemaId : String) : IO Unit := do
    let source :=
      "import ProofForgeV2\n" ++
      "open ProofForgeV2.Language\n" ++
      s!"program {label} where\n" ++ body
    let parsed ← liftResult (← session.selectProgramV1
      source s!"<soroban-{label}>" s!"Tests.Soroban{label}" none)
    let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
    match planSoroban compiled with
    | .error e =>
        expect (e.render.contains needle)
          s!"{label} Plan FC must contain '{needle}', got: {e.render}"
        expect (e.render.contains schemaId)
          s!"{label} Plan FC must name '{schemaId}', got: {e.render}"
    | .ok _ =>
        throw <| IO.userError
          s!"{label} must Plan fail closed (no Soroban context host)"
  let ctxBody (place : String) : String :=
    "  state pad : UInt64\n" ++
      "  init() do\n" ++
      "    pad := 0\n" ++
      "  entry probe() : UInt64 do\n" ++
      "    return " ++ place ++ "\n" ++
      "  view get() : UInt64 do\n" ++
      "    return pad\n"
  expectPlanFc "UnixTimeSoroban" (ctxBody "context.unixTimeSeconds")
    "has no Soroban host binding" "proof-forge.context.unix-time-seconds.v1"
  expectPlanFc "BlockHeightSoroban" (ctxBody "context.blockHeight")
    "has no Soroban host binding" "proof-forge.context.block-height.v1"
  expectPlanFc "AttachedValueSoroban" (ctxBody "context.attachedValue")
    "has no Soroban host binding" "proof-forge.context.attached-value.v1"
  expectPlanFc "ChainIdSoroban" (ctxBody "context.chainId")
    "has no Soroban host binding" "proof-forge.context.chain-id.v1"

/-- SYS-E2: Soroban has no native vault host. `pf.assets.native.balanceOfSelf`
    stays Plan fail closed. token/U128 stay on the generic envRead envelope
    (Principal mint / UInt128 rejected first). -/
unsafe def testEnvReadNativeStayFailClosed : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program EnvReadBalanceSoroban where\n" ++
    "  requires extension pf.assets version \"1.1.0\"\n" ++
    "    digest \"sha256:59412f732e634b0256a02c9ec23a253c38478879d6b74b279e750b220879aaa9\"\n" ++
    "  state count : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  view nativeBalance() : UInt64 do\n" ++
    "    return pf.assets.native.balanceOfSelf()\n" ++
    "  entry setCount(newCount : UInt64) : UInt64 do\n" ++
    "    count := newCount\n" ++
    "    return count\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<soroban-env-read-native>" "Tests.EnvReadBalanceSoroban" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  match planSoroban compiled with
  | .error e =>
      expect (e.render.contains "has no Soroban host binding")
        s!"EnvReadBalanceSoroban Plan FC must contain 'has no Soroban host binding', got: {e.render}"
      expect (e.render.contains "envRead" || e.render.contains "nativeVaultBalance")
        s!"EnvReadBalanceSoroban Plan FC must name envRead/nativeVaultBalance, got: {e.render}"
  | .ok _ =>
      throw <| IO.userError
        "EnvReadBalanceSoroban must Plan fail closed (no Soroban vault host)"

/-- SOR-1a: product capability → materialize → Finalize stays S0 zero-tool.
    `{name}.rs` is a source recipe, not a cargo package; Finalize must not
    invent Wasm extras or claim deployable. -/
unsafe def testCapabilityProductPath : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program StateCell where\n" ++
    "  state count : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry increment(delta : UInt64) : UInt64 do\n" ++
    "    count := count + delta\n" ++
    "    return count\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<soroban-capability>" "Tests.SorobanCapability" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let selection ← liftResult <|
    Targets.BuildSelectionV1.resolveBuildSelectionV1 TargetId.soroban none
  expect (selection.codegenProfile == CodegenProfileId.sorobanSourceU64V1)
    "Soroban selection must bind soroban-source-u64-v1"
  let capability ← liftResult <|
    Targets.resolveEngineeringRequirementsV1 selection compiled
  let artifacts ← liftResult <| Targets.materializeResult capability
  expect (MaterializedArtifactsV1.targetIdOf artifacts == TargetId.soroban)
    "materialized artifacts must bind TargetId.soroban"
  let files := MaterializedArtifactsV1.filesOf artifacts
  expect (files.size == 1 && files[0]!.path == "StateCell.rs")
    "S0 materialize must emit exactly StateCell.rs (not a cargo package)"
  let finalized ← Targets.finalizeMaterializedArtifactsV1
    capability artifacts (System.FilePath.mk ".")
  expect (!FinalizedArtifactsV1.deployableOf finalized)
    "Soroban S0 finalization must remain non-deployable"
  expect (FinalizedArtifactsV1.extraFilesOf finalized).isEmpty
    "Soroban S0 zero-tool finalization must add no files"
  let note := FinalizedArtifactsV1.evidenceNoteOf finalized
  expect (note.contains "stellar-cli" || note.contains "Wasm toolchain")
    s!"Soroban S0 evidence must cite stellar-cli or Wasm toolchain, got: {note}"

/-- SOR-1a: grammar-valid but unregistered profile stays unknown.
    Do not reserve a `soroban-wasm-*` CodegenProfileId. -/
unsafe def testUnknownProfileFailClosed : IO Unit := do
  match CodegenProfileId.parse? "not-a-real-profile-v1" with
  | none =>
      throw <| IO.userError "not-a-real-profile-v1 must remain grammar-valid"
  | some unknown =>
      match Targets.BuildSelectionV1.resolveBuildSelectionV1
          TargetId.soroban (some unknown) with
      | .error e =>
          expect (e.code == "PF-PROFILE-UNKNOWN")
            s!"unknown Soroban profile must be PF-PROFILE-UNKNOWN, got {e.code}: {e.render}"
      | .ok sel =>
          throw <| IO.userError
            s!"unknown Soroban profile must fail closed, got {sel.codegenProfile}"

/-- Homogeneous Array UInt64 2 flatten: two instance `u64` keys, no Vec. -/
unsafe def testArrayBoxFlatten : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program ArrayBox where\n" ++
    "  state slots : Array UInt64 2\n" ++
    "  init(a : UInt64, b : UInt64) do\n" ++
    "    slots[0] := a\n" ++
    "    slots[1] := b\n" ++
    "  entry set0(v : UInt64) : UInt64 do\n" ++
    "    slots[0] := v\n" ++
    "    return slots[0]\n" ++
    "  view get0() : UInt64 do\n" ++
    "    return slots[0]\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<soroban-array-box>" "Tests.SorobanArrayBox" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planSoroban compiled
  expect (!plan.signedNumeric) "ArrayBox stays unsigned"
  expect (plan.states.map (·.name) == #["slots_0", "slots_1"])
    "Array UInt64 2 must flatten to slots_0/slots_1 Plan leaves"
  match plan.initializer with
  | some initFn =>
      expect (initFn.stores.size == 2)
        "ArrayBox init must store both flattened leaves"
  | none => throw <| IO.userError "ArrayBox must have an initializer"
  liftResult <| Targets.Soroban.validatePlan plan
  let files ← liftResult <| buildSoroban compiled
  let some rsFile := files.find? (fun f => f.path == "ArrayBox.rs") |
    throw <| IO.userError "soroban: missing ArrayBox.rs"
  let rs := rsFile.contents
  expect (rs.contains "symbol_short!(\"slots_0\")")
    "ArrayBox.rs must use instance key slots_0"
  expect (rs.contains "symbol_short!(\"slots_1\")")
    "ArrayBox.rs must use instance key slots_1"
  expect (rs.contains "unwrap_or(0_u64)")
    "flattened Array leaves stay unsigned u64 instance fields"
  expect (!rs.contains "Vec<")
    "Array flatten must not emit a Rust Vec"
  expect (!rs.contains "[u64;")
    "Array flatten must not emit a Rust array type"
  expect (!rs.contains "i64")
    "unsigned ArrayBox must not emit i64"

/-- N=9 exceeds the 1..8 flatten cap. -/
unsafe def testArrayN9FailClosed : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program ArrayNine where\n" ++
    "  state slots : Array UInt64 9\n" ++
    "  init() do\n" ++
    "    slots[0] := 0\n" ++
    "  entry set0(v : UInt64) : UInt64 do\n" ++
    "    slots[0] := v\n" ++
    "    return slots[0]\n" ++
    "  view get0() : UInt64 do\n" ++
    "    return slots[0]\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<soroban-array-n9>" "Tests.SorobanArrayNine" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  match planSoroban compiled with
  | .error (.planInvariant .soroban msg) =>
      expect (msg.contains "cap" || msg.contains "container")
        s!"Array UInt64 9 must cite cap/container, got: {msg}"
  | .error e => throw <| IO.userError s!"expected planInvariant .soroban, got {e.render}"
  | .ok _ => throw <| IO.userError "Array UInt64 9 must fail closed at Soroban plan"

/-- Array of Int64 / UInt32 is not S0 flatten. -/
unsafe def testArrayNonUInt64ElementFailClosed : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let expectElFc (label ty : String) : IO Unit := do
    let source :=
      "import ProofForgeV2\n" ++
      "open ProofForgeV2.Language\n" ++
      s!"program {label} where\n" ++
      s!"  state slots : Array {ty} 2\n" ++
      "  init() do\n" ++
      "    slots[0] := 0\n" ++
      "  entry set0() : UInt64 do\n" ++
      "    return 0\n"
    let parsed ← liftResult (← session.selectProgramV1
      source s!"<soroban-{label}>" s!"Tests.Soroban{label}" none)
    let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
    match planSoroban compiled with
    | .error (.planInvariant .soroban msg) =>
        expect (msg.contains "element" || msg.contains "UInt64" || msg.contains "width")
          s!"{label} must cite element/UInt64, got: {msg}"
    | .error e =>
        throw <| IO.userError s!"expected planInvariant .soroban for {label}, got {e.render}"
    | .ok _ =>
        throw <| IO.userError s!"Array {ty} must fail closed at Soroban plan"
  expectElFc "ArrayInt64El" "Int64"
  expectElFc "ArrayUInt32El" "UInt32"

/-- Array return stays fail closed (only state flattens). -/
unsafe def testArrayReturnFailClosed : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program ArrayRet where\n" ++
    "  state slots : Array UInt64 2\n" ++
    "  init() do\n" ++
    "    slots[0] := 0\n" ++
    "  entry set0(v : UInt64) : UInt64 do\n" ++
    "    slots[0] := v\n" ++
    "    return slots[0]\n" ++
    "  view get() : Array UInt64 2 do\n" ++
    "    return slots\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<soroban-array-ret>" "Tests.SorobanArrayRet" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  match planSoroban compiled with
  | .error (.planInvariant .soroban msg) =>
      expect (msg.contains "Array/Map return" || msg.contains "Array return")
        s!"Array return must name Array/Map return, got: {msg}"
  | .error e => throw <| IO.userError s!"expected planInvariant .soroban, got {e.render}"
  | .ok _ => throw <| IO.userError "Array return must fail closed at Soroban plan"

/-- signedNumeric Int64 + Array state is unsigned-flatten only. -/
unsafe def testSignedNumericArrayStateFailClosed : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program SignedArrayMix where\n" ++
    "  state count : Int64\n" ++
    "  state slots : Array UInt64 2\n" ++
    "  init() do\n" ++
    "    count := 0\n" ++
    "    slots[0] := 0\n" ++
    "  entry bump(d : Int64) : Int64 do\n" ++
    "    count := count + d\n" ++
    "    return count\n" ++
    "  view get() : Int64 do\n" ++
    "    return count\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<soroban-signed-array>" "Tests.SorobanSignedArray" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  match planSoroban compiled with
  | .error (.planInvariant .soroban msg) =>
      expect (msg.contains "Array" && msg.contains "UInt64")
        s!"mixed Int64+Array UInt64 must cite Array/UInt64, got: {msg}"
  | .error e => throw <| IO.userError s!"expected planInvariant .soroban, got {e.render}"
  | .ok _ => throw <| IO.userError "signedNumeric + Array state must fail closed"

/-- 10-byte state name + `_0` exceeds `symbol_short!` 9-byte limit; never truncate. -/
unsafe def testArrayLongNameSymbolShortFailClosed : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program LongLeaf where\n" ++
    "  state abcdefghij : Array UInt64 2\n" ++
    "  init() do\n" ++
    "    abcdefghij[0] := 0\n" ++
    "  entry set0(v : UInt64) : UInt64 do\n" ++
    "    abcdefghij[0] := v\n" ++
    "    return abcdefghij[0]\n" ++
    "  view get0() : UInt64 do\n" ++
    "    return abcdefghij[0]\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<soroban-long-leaf>" "Tests.SorobanLongLeaf" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  match planSoroban compiled with
  | .error (.planInvariant .soroban msg) =>
      expect (msg.contains "symbol_short")
        s!"long flattened leaf must name symbol_short!, got: {msg}"
      expect (msg.contains "abcdefghij_0")
        s!"long flattened leaf must name abcdefghij_0, got: {msg}"
  | .error e => throw <| IO.userError s!"expected planInvariant .soroban, got {e.render}"
  | .ok _ => throw <| IO.userError "10-byte Array state name must fail closed (no truncate)"

/-- Option UInt64 state: two instance `u64` keys `o_tag`/`o_p0`, no Vec. -/
unsafe def testOptBoxAdmit : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program OptBox where\n" ++
    "  state o : Option UInt64\n" ++
    "  init() do\n" ++
    "    o := Option.none()\n" ++
    "  entry setSome(v : UInt64) : UInt64 do\n" ++
    "    o := Option.some(v)\n" ++
    "    return v\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<soroban-opt-box>" "Tests.SorobanOptBox" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planSoroban compiled
  expect (!plan.signedNumeric) "OptBox stays unsigned"
  expect (plan.states.map (·.name) == #["o_tag", "o_p0"])
    "Option UInt64 must flatten to o_tag/o_p0 Plan leaves"
  match plan.initializer with
  | some initFn =>
      expect (initFn.stores.size == 2)
        "OptBox init must store both tag and payload leaves"
  | none => throw <| IO.userError "OptBox must have an initializer"
  let some setSome := plan.entries[0]? |
    throw <| IO.userError "missing setSome entry"
  expect (setSome.stores.size == 2)
    "OptBox setSome must store both Option leaves"
  liftResult <| Targets.Soroban.validatePlan plan
  let files ← liftResult <| buildSoroban compiled
  let some rsFile := files.find? (fun f => f.path == "OptBox.rs") |
    throw <| IO.userError "soroban: missing OptBox.rs"
  let rs := rsFile.contents
  expect (rs.contains "symbol_short!(\"o_tag\")")
    "OptBox.rs must use instance key o_tag"
  expect (rs.contains "symbol_short!(\"o_p0\")")
    "OptBox.rs must use instance key o_p0"
  expect (rs.contains "unwrap_or(0_u64)")
    "Option leaves stay unsigned u64 instance fields"
  expect (!rs.contains "Vec<")
    "Option flatten must not emit a Rust Vec"
  expect (!rs.contains "Option<")
    "Option flatten must not emit a Rust Option type"
  expect (!rs.contains "i64")
    "unsigned OptBox must not emit i64"

/-- Option of Int64 is not S0 flatten. -/
unsafe def testOptionInt64ElementFailClosed : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program OptInt64El where\n" ++
    "  state o : Option Int64\n" ++
    "  init() do\n" ++
    "    o := Option.none()\n" ++
    "  entry setSome() : UInt64 do\n" ++
    "    return 0\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<soroban-opt-int64>" "Tests.SorobanOptInt64El" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  match planSoroban compiled with
  | .error (.planInvariant .soroban msg) =>
      expect (msg.contains "payload" || msg.contains "UInt64" || msg.contains "Option")
        s!"Option Int64 must cite payload/UInt64/Option, got: {msg}"
  | .error e => throw <| IO.userError s!"expected planInvariant .soroban, got {e.render}"
  | .ok _ => throw <| IO.userError "Option Int64 must fail closed at Soroban plan"

/-- Option return stays fail closed (only state flattens). -/
unsafe def testOptionReturnFailClosed : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program OptRet where\n" ++
    "  state o : Option UInt64\n" ++
    "  init() do\n" ++
    "    o := Option.none()\n" ++
    "  entry peek() : Option UInt64 do\n" ++
    "    return o\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<soroban-opt-ret>" "Tests.SorobanOptRet" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  match planSoroban compiled with
  | .error (.planInvariant .soroban msg) =>
      expect (msg.contains "Option return is outside S0")
        s!"Option return must name Option return is outside S0, got: {msg}"
  | .error e => throw <| IO.userError s!"expected planInvariant .soroban, got {e.render}"
  | .ok _ => throw <| IO.userError "Option return must fail closed at Soroban plan"

/-- signedNumeric Int64 + Option state is unsigned-flatten only. -/
unsafe def testSignedNumericOptionStateFailClosed : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program SignedOptMix where\n" ++
    "  state count : Int64\n" ++
    "  state o : Option UInt64\n" ++
    "  init() do\n" ++
    "    count := 0\n" ++
    "    o := Option.none()\n" ++
    "  entry bump(d : Int64) : Int64 do\n" ++
    "    count := count + d\n" ++
    "    return count\n" ++
    "  view get() : Int64 do\n" ++
    "    return count\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<soroban-signed-opt>" "Tests.SorobanSignedOpt" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  match planSoroban compiled with
  | .error (.planInvariant .soroban msg) =>
      expect (msg.contains "Option" && msg.contains "UInt64")
        s!"mixed Int64+Option UInt64 must cite Option/UInt64, got: {msg}"
  | .error e => throw <| IO.userError s!"expected planInvariant .soroban, got {e.render}"
  | .ok _ => throw <| IO.userError "signedNumeric + Option state must fail closed"

/-- Map UInt64 UInt64 dense cap-8: 24 Plan leaves, empty + IndexSet. -/
unsafe def testMapMiniAdmit : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program MapMini where\n" ++
    "  state m : Map UInt64 UInt64\n" ++
    "  init() do\n" ++
    "    m := Map.empty()\n" ++
    "  entry put(k : UInt64, v : UInt64) : UInt64 do\n" ++
    "    m[k] := v\n" ++
    "    return v\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<soroban-map-mini>" "Tests.SorobanMapMini" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planSoroban compiled
  expect (!plan.signedNumeric) "MapMini stays unsigned"
  expect (plan.states.size == 24)
    s!"Map UInt64 cap-8 must flatten to 24 leaves, got {plan.states.size}"
  expect (plan.states[0]!.name == "m_0" && plan.states[23]!.name == "m_23")
    "Map flatten leaf names must be m_0..m_23"
  match plan.initializer with
  | some initFn =>
      expect (initFn.stores.size == 24)
        "MapMini init must store all 24 Map leaves"
  | none => throw <| IO.userError "MapMini must have an initializer"
  expect (plan.entries.size == 1) "MapMini has one entry"
  expect (plan.entries[0]!.stores.size == 24)
    "MapMini put must store all 24 Map leaves"
  expect (plan.entries[0]!.checks.size ≥ 1)
    "MapMini put must check cap-8 overflow"
  liftResult <| Targets.Soroban.validatePlan plan
  let files ← liftResult <| buildSoroban compiled
  let some rsFile := files.find? (fun f => f.path == "MapMini.rs") |
    throw <| IO.userError "soroban: missing MapMini.rs"
  let rs := rsFile.contents
  expect (rs.contains "symbol_short!(\"m_0\")")
    "MapMini.rs must use instance key m_0"
  expect (rs.contains "symbol_short!(\"m_23\")")
    "MapMini.rs must use instance key m_23"
  expect (!rs.contains "Vec<")
    "Map flatten must not emit a Rust Vec"
  expect (!rs.contains "HashMap")
    "Map flatten must not emit a Rust HashMap"

/-- Map of Int64 stays fail closed. -/
unsafe def testMapInt64ElementFailClosed : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program MapInt where\n" ++
    "  state m : Map UInt64 Int64\n" ++
    "  init() do\n" ++
    "    m := Map.empty()\n" ++
    "  entry put(k : UInt64, v : UInt64) : UInt64 do\n" ++
    "    return v\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<soroban-map-int>" "Tests.SorobanMapInt" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  match planSoroban compiled with
  | .error (.planInvariant .soroban msg) =>
      expect (msg.contains "Map state admits only Map UInt64 UInt64" ||
          msg.contains "payload")
        s!"Map Int64 must cite Map UInt64 UInt64 or payload, got: {msg}"
  | .error e => throw <| IO.userError s!"expected planInvariant .soroban, got {e.render}"
  | .ok _ => throw <| IO.userError "Map Int64 must fail closed at Soroban plan"

/-- Map entry return stays outside S0. -/
unsafe def testMapReturnFailClosed : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program MapRet where\n" ++
    "  state m : Map UInt64 UInt64\n" ++
    "  init() do\n" ++
    "    m := Map.empty()\n" ++
    "  entry peek() : Map UInt64 UInt64 do\n" ++
    "    return m\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<soroban-map-ret>" "Tests.SorobanMapRet" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  match planSoroban compiled with
  | .error (.planInvariant .soroban msg) =>
      expect (msg.contains "Array/Map return is outside S0")
        s!"Map return must cite Array/Map return is outside S0, got: {msg}"
  | .error e => throw <| IO.userError s!"expected planInvariant .soroban, got {e.render}"
  | .ok _ => throw <| IO.userError "Map return must fail closed at Soroban plan"

/-- signedNumeric Int64 programs cannot carry Map state. -/
unsafe def testSignedNumericMapStateFailClosed : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program MixMap where\n" ++
    "  state n : Int64\n" ++
    "  state m : Map UInt64 UInt64\n" ++
    "  init() do\n" ++
    "    n := 0\n" ++
    "    m := Map.empty()\n" ++
    "  entry bump(d : Int64) : Int64 do\n" ++
    "    n := n + d\n" ++
    "    return n\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<soroban-signed-map>" "Tests.SorobanMixMap" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  match planSoroban compiled with
  | .error (.planInvariant .soroban msg) =>
      expect (msg.contains "Map" && msg.contains "UInt64")
        s!"mixed Int64+Map UInt64 must cite Map/UInt64, got: {msg}"
  | .error e => throw <| IO.userError s!"expected planInvariant .soroban, got {e.render}"
  | .ok _ => throw <| IO.userError "signedNumeric+Map must fail closed at Soroban plan"

unsafe def testArrInt64Flatten : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program ArrInt64 where\n" ++
    "  state slots : Array Int64 2\n" ++
    "  init(a : Int64, b : Int64) do\n" ++
    "    slots[0] := a\n" ++
    "    slots[1] := b\n" ++
    "  entry set0(v : Int64) : Int64 do\n" ++
    "    slots[0] := v\n" ++
    "    return slots[0]\n" ++
    "  view get0() : Int64 do\n" ++
    "    return slots[0]\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<soroban-arr-int64>" "Tests.SorobanArrInt64" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planSoroban compiled
  expect plan.signedNumeric "ArrInt64 Plan is signed"
  expect (plan.states.map (·.name) == #["slots_0", "slots_1"])
    "Array Int64 2 flattens to slots_0/slots_1"
  liftResult <| Targets.Soroban.validatePlan plan
  let files ← liftResult <| buildSoroban compiled
  let some rsFile := files.find? (fun f => f.path == "ArrInt64.rs") |
    throw <| IO.userError "soroban: missing ArrInt64.rs"
  expect (rsFile.contents.contains "unwrap_or(0_i64)") "signed Array emits i64"
  expect (!rsFile.contents.contains "Vec<") "no Rust Vec"

unsafe def testOptInt64Flatten : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program OptInt64 where\n" ++
    "  state o : Option Int64\n" ++
    "  init() do\n" ++
    "    o := Option.none()\n" ++
    "  entry setSome(v : Int64) : Int64 do\n" ++
    "    o := Option.some(v)\n" ++
    "    return v\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<soroban-opt-int64>" "Tests.SorobanOptInt64" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planSoroban compiled
  expect plan.signedNumeric "OptInt64 Plan is signed"
  expect (plan.states.map (·.name) == #["o_tag", "o_p0"])
    "Option Int64 flattens to o_tag/o_p0"
  liftResult <| Targets.Soroban.validatePlan plan
  let files ← liftResult <| buildSoroban compiled
  let some rsFile := files.find? (fun f => f.path == "OptInt64.rs") |
    throw <| IO.userError "soroban: missing OptInt64.rs"
  expect (rsFile.contents.contains "unwrap_or(0_i64)") "signed Option emits i64"
  expect (!rsFile.contents.contains "Option<") "no Rust Option"

unsafe def testMapInt64Flatten : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program MapInt64 where\n" ++
    "  state m : Map Int64 Int64\n" ++
    "  init() do\n" ++
    "    m := Map.empty()\n" ++
    "  entry put(k : Int64, v : Int64) : Int64 do\n" ++
    "    m[k] := v\n" ++
    "    return v\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<soroban-map-int64>" "Tests.SorobanMapInt64" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planSoroban compiled
  expect plan.signedNumeric "MapInt64 Plan is signed"
  expect (plan.states.size == 24) "Map Int64 flattens to 24 leaves"
  liftResult <| Targets.Soroban.validatePlan plan
  let files ← liftResult <| buildSoroban compiled
  let some rsFile := files.find? (fun f => f.path == "MapInt64.rs") |
    throw <| IO.userError "soroban: missing MapInt64.rs"
  expect (rsFile.contents.contains "unwrap_or(0_i64)") "signed Map emits i64"
  expect (!rsFile.contents.contains "HashMap") "no HashMap"

unsafe def testArrayInt64ReturnFailClosed : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program ArrInt64Ret where\n" ++
    "  state slots : Array Int64 2\n" ++
    "  init() do\n" ++
    "    slots[0] := 0\n" ++
    "  entry peek(v : Int64) : Array Int64 2 do\n" ++
    "    return slots\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<soroban-arr-int64-ret>" "Tests.SorobanArrInt64Ret" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  match planSoroban compiled with
  | .error (.planInvariant .soroban msg) =>
      expect (msg.contains "Array/Map return" || msg.contains "Array return")
        s!"Array Int64 return, got: {msg}"
  | .error e => throw <| IO.userError s!"expected planInvariant .soroban, got {e.render}"
  | .ok _ => throw <| IO.userError "Array Int64 return must fail closed"

unsafe def testArrayInt64N9FailClosed : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program ArrInt64Nine where\n" ++
    "  state slots : Array Int64 9\n" ++
    "  init() do\n" ++
    "    slots[0] := 0\n" ++
    "  entry set0(v : Int64) : Int64 do\n" ++
    "    slots[0] := v\n" ++
    "    return slots[0]\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<soroban-arr-int64-n9>" "Tests.SorobanArrInt64Nine" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  match planSoroban compiled with
  | .error (.planInvariant .soroban msg) =>
      expect (msg.contains "cap" || msg.contains "1..8")
        s!"Array Int64 9, got: {msg}"
  | .error e => throw <| IO.userError s!"expected planInvariant .soroban, got {e.render}"
  | .ok _ => throw <| IO.userError "Array Int64 9 must fail closed"

unsafe def testPrincipalIdentityLeaves : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program PrincipalMix where\n" ++
    "  state owner : Principal\n" ++
    "  init(initial : Principal) do\n" ++
    "    owner := initial\n" ++
    "  entry set(who : Principal) : Bool do\n" ++
    "    owner := who\n" ++
    "    return true\n" ++
    "  entry eq(a : Principal, b : Principal) : Bool do\n" ++
    "    return a == b\n" ++
    "  entry matchesOwner(who : Principal) : Bool do\n" ++
    "    return owner == who\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<soroban-principal>" "Tests.SorobanPrincipal" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planSoroban compiled
  expect (!plan.signedNumeric) "PrincipalMix stays unsigned"
  expect (plan.states.map (·.name) ==
      #["owner_len", "owner_w0", "owner_w1", "owner_w2", "owner_w3",
        "owner_w4", "owner_w5", "owner_w6", "owner_w7"])
    "Principal must flatten to owner_len + owner_w0..w7"
  liftResult <| Targets.Soroban.validatePlan plan
  let files ← liftResult <| buildSoroban compiled
  expect (!files.isEmpty) "PrincipalMix must materialize Soroban files"
  let retSource :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program PrincipalReturn where\n" ++
    "  state owner : Principal\n" ++
    "  init(initial : Principal) do\n" ++
    "    owner := initial\n" ++
    "  view getOwner() : Principal do\n" ++
    "    return owner\n"
  let parsedRet ← liftResult (← session.selectProgramV1
    retSource "<soroban-principal-ret>" "Tests.SorobanPrincipalReturn" none)
  let compiledRet ← liftResult <| Compiler.compileValidatedSourceV1 parsedRet
  match planSoroban compiledRet with
  | .ok _ => throw <| IO.userError "Principal return must fail closed"
  | .error e =>
      expect (e.render.contains "Principal")
        s!"Principal return must cite Principal, got {e.render}"

unsafe def run : IO Unit := do
  testStateCellSorobanSource
  testInt64CellSorobanSource
  testMixedInt64UInt64Fc
  testMultiWidthFailClosed
  testInvariantFailClosed
  testCallFailClosed
  testCryptoSha256StayFailClosed
  testContextReadStayFailClosed
  testEnvReadNativeStayFailClosed
  testCapabilityProductPath
  testUnknownProfileFailClosed
  testArrayBoxFlatten
  testArrInt64Flatten
  testArrayN9FailClosed
  testArrayInt64N9FailClosed
  testArrayNonUInt64ElementFailClosed
  testArrayReturnFailClosed
  testArrayInt64ReturnFailClosed
  testSignedNumericArrayStateFailClosed
  testArrayLongNameSymbolShortFailClosed
  testOptBoxAdmit
  testOptInt64Flatten
  testOptionInt64ElementFailClosed
  testOptionReturnFailClosed
  testSignedNumericOptionStateFailClosed
  testMapMiniAdmit
  testMapInt64Flatten
  testMapInt64ElementFailClosed
  testMapReturnFailClosed
  testSignedNumericMapStateFailClosed
  testPrincipalIdentityLeaves
  IO.println "Tests.Materialization.SorobanPlanV1: ok"

end Tests.Materialization.SorobanPlanV1
