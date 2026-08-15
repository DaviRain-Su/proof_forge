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
  IO.println "Tests.Materialization.SorobanPlanV1: ok"

end Tests.Materialization.SorobanPlanV1
