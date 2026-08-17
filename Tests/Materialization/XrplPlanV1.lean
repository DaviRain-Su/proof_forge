/-
  XRPL Q0/Q1 target leaf tests (ADR-0049 + ADR-0050): Plan/IR/emitter over
  retained SemanticProgramV1. Uses planFromCompiledSemanticV1 /
  buildFromCompiledSemanticV1 plus the full capability/materialize/finalize
  product path for both the default zero-tool source profile and the opt-in
  `xrpl-bedrock-wasm-u64-v1` build profile.
-/
import ProofForgeV2
import ProofForgeV2.Targets.Xrpl
import ProofForgeV2.Targets.Xrpl.FinalizeV1
import ProofForgeV2.Targets.BuildSelectionV1
import ProofForgeV2.Core.TargetIdentityV1
import Tests.Language.ParserSession
import Tests.Compiler.ValidatedSourceV1Pipeline

namespace Tests.Materialization.XrplPlanV1

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Targets

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def liftResult (result : CompileResult α) : IO α :=
  match result with
  | .ok value => pure value
  | .error error => throw <| IO.userError error.render

private def planXrpl (compiled : CompiledSemanticV1) :
    CompileResult Targets.Xrpl.Plan :=
  Targets.Xrpl.planFromCompiledSemanticV1 compiled

private def buildXrpl (compiled : CompiledSemanticV1) :
    CompileResult (Array OutputFile) :=
  Targets.Xrpl.buildFromCompiledSemanticV1 compiled

private def stateCellSource : String :=
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

unsafe def testStateCellXrplSource : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let parsed ← liftResult (← session.selectProgramV1
    stateCellSource "<xrpl-state-cell>" "Tests.XrplStateCell" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planXrpl compiled
  expect (plan.states.map (·.name) == #["count"])
    "StateCell XRPL plan must carry the count state field"
  expect (plan.entries.map (·.name) == #["increment"])
    "StateCell XRPL plan must carry the increment entry"
  expect (plan.views.map (·.name) == #["get"])
    "StateCell XRPL plan must carry the get view"
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
  liftResult <| Targets.Xrpl.validatePlan plan
  let files ← liftResult <| buildXrpl compiled
  expect (files.size == 1) "XRPL Q0 must emit exactly one file"
  let some rsFile := files.find? (·.path == "StateCell.rs") |
    throw <| IO.userError "xrpl: missing StateCell.rs"
  expect (rsFile.mediaType == "text/x-rust")
    "StateCell.rs media type must be text/x-rust"
  let rs := rsFile.contents
  expect (rs.contains "xrpl-bedrock-source-u64-v1")
    "source must cite the frozen Q0 profile"
  expect (rs.contains "#![cfg_attr(target_arch = \"wasm32\", no_std)]")
    "source must declare wasm32 no_std"
  expect (rs.contains "use xrpl_wasm_std::core::data::codec::{get_data, set_data};")
    "source must import get_data/set_data"
  expect (rs.contains "use xrpl_wasm_std::core::current_tx::contract_call::get_current_contract_call;")
    "source must import get_current_contract_call"
  expect (rs.contains "const count_KEY: &str = \"count\";")
    "source must bind the count storage key"
  expect (rs.contains "#[unsafe(no_mangle)]")
    "source must export via unsafe no_mangle"
  expect (rs.contains "pub extern \"C\" fn increment(delta: u64) -> i32")
    "source must export increment as extern C i32"
  expect (rs.contains "/// @xrpl-function increment")
    "source may carry the Bedrock doc annotation, not a Rust macro"
  expect (!rs.contains "#[xrpl_function]")
    "source must not invent a xrpl_function attribute"
  expect (!rs.contains "host_storage")
    "source must not invent a host_storage API"
  expect (!rs.contains "openvm::")
    "source must not reuse the OpenVM guest template"
  expect (!rs.contains "soroban_sdk")
    "source must not reuse the Soroban SDK template"
  expect (rs.contains "checked_add(delta).ok_or(1i32)?")
    "increment must use checked_add with overflow code 1"
  expect (rs.contains "pub extern \"C\" fn get() -> i32")
    "source must export get as a zero-arg view"

unsafe def testMaterializeDeterminism : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let parsed ← liftResult (← session.selectProgramV1
    stateCellSource "<xrpl-det>" "Tests.XrplDet" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let files1 ← liftResult <| buildXrpl compiled
  let files2 ← liftResult <| buildXrpl compiled
  expect (files1 == files2)
    "XRPL materialize must be deterministic"
  let plan1 ← liftResult <| planXrpl compiled
  let plan2 ← liftResult <| planXrpl compiled
  expect (plan1 == plan2)
    "XRPL plan lower must be deterministic"
  match Targets.Xrpl.engineeringXrplPlanDigestV1 plan1 with
  | .ok d1 =>
      match Targets.Xrpl.engineeringXrplPlanDigestV1 plan2 with
      | .ok d2 => expect (d1 == d2) "plan digest must be deterministic"
      | .error e => throw <| IO.userError e
  | .error e => throw <| IO.userError e

unsafe def testSelectionBindsDefaultSourceProfile : IO Unit := do
  let selection ← liftResult <|
    Targets.BuildSelectionV1.resolveBuildSelectionV1 TargetId.xrpl none
  expect (selection.codegenProfile == CodegenProfileId.xrplBedrockSourceU64V1)
    "XRPL selection must bind the default source profile"
  expect (selection.kind == TargetKind.xrpl)
    "XRPL selection must bind TargetKind.xrpl"

private unsafe def wasmCompiledStateCell : IO CompiledSemanticV1 := do
  let session ← Tests.Language.ParserSession.shared
  let parsed ← liftResult (← session.selectProgramV1
    stateCellSource "<xrpl-wasm>" "Tests.XrplWasm" none)
  liftResult <| Compiler.compileValidatedSourceV1 parsed

/-- ADR-0050 Q1: selecting the explicit wasm profile shares the exact same
    Plan/base `{name}.rs` as the default source profile. -/
unsafe def testWasmProfileSelection : IO Unit := do
  let compiled ← wasmCompiledStateCell
  let selection ← liftResult <|
    Targets.BuildSelectionV1.resolveBuildSelectionV1
      TargetId.xrpl (some CodegenProfileId.xrplBedrockWasmU64V1)
  expect (selection.codegenProfile == CodegenProfileId.xrplBedrockWasmU64V1)
    "XRPL selection must bind the explicit wasm profile when requested"
  let capability ← liftResult <|
    Targets.resolveEngineeringRequirementsV1 selection compiled
  let plan ← liftResult <| Targets.Xrpl.planFromCapability capability
  expect (plan.programName == "StateCell")
    "XRPL wasm profile must retain the compiled artifact name"
  let artifacts ← liftResult <| Targets.materializeResult capability
  expect (MaterializedArtifactsV1.codegenProfileIdOf artifacts ==
      CodegenProfileId.xrplBedrockWasmU64V1)
    "XRPL wasm materialize must bind the wasm profile"
  let files := MaterializedArtifactsV1.filesOf artifacts
  expect (files.size == 1)
    "XRPL wasm profile must emit the same single .rs base file as the source profile"
  expect (files[0]!.path == "StateCell.rs")
    "XRPL wasm profile must keep StateCell.rs as the base artifact"

/-- ADR-0050 Q1 Finalize: missing rustc/cargo fails closed with
    `PF-TOOLCHAIN-MISSING`; when ambient cargo is present, the
    `wasm32-unknown-unknown` extra is staged at `xrpl-build/{program}.wasm`.
    Host-optional in the success arm: cargo may be present without the wasm
    target or a fetchable craft rev, so a build failure there is an honest
    skip rather than a hard failure. -/
unsafe def testWasmProfileFinalize : IO Unit := do
  let compiled ← wasmCompiledStateCell
  let selection ← liftResult <|
    Targets.BuildSelectionV1.resolveBuildSelectionV1
      TargetId.xrpl (some CodegenProfileId.xrplBedrockWasmU64V1)
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
    let cargo? ← Targets.Xrpl.FinalizeV1.resolveCargoPathV1
    let rustc? ← Targets.Xrpl.FinalizeV1.resolveRustcPathV1
    match cargo?, rustc? with
    | none, _ | _, none => do
        let outcome ←
          try
            let _ ← Targets.finalizeMaterializedArtifactsV1 capability artifacts stagingDir
            pure (Except.ok () : Except String Unit)
          catch e => pure (Except.error (toString e))
        match outcome with
        | .ok () =>
            throw <| IO.userError "XRPL wasm finalize must fail without rustc/cargo"
        | .error msg =>
            expect (msg.contains "PF-TOOLCHAIN-MISSING")
              s!"missing rustc/cargo must fail closed with PF-TOOLCHAIN-MISSING, got: {msg}"
    | some path, some _ => do
        let outcome ←
          try
            let finalized ←
              Targets.finalizeMaterializedArtifactsV1 capability artifacts stagingDir
            pure (Except.ok finalized : Except String FinalizedArtifactsV1)
          catch e => pure (Except.error (toString e))
        match outcome with
        | .error msg =>
            if msg.contains "PF-TOOLCHAIN-MISSING" then
              IO.println
                s!"  skipped: ambient cargo present but wasm32-unknown-unknown missing: {msg}"
            else
              IO.println
                s!"  skipped: ambient cargo present but XRPL wasm build failed: {msg}"
        | .ok finalized =>
            expect (!FinalizedArtifactsV1.deployableOf finalized)
              "XRPL wasm finalization must remain non-deployable"
            let extras := FinalizedArtifactsV1.extraFilesOf finalized
            expect (extras == #["xrpl-build/StateCell.wasm"])
              s!"XRPL wasm extras must use the stable xrpl-build/* path, got {extras}"
            let wasmBytes ← IO.FS.readBinFile (stagingDir / "xrpl-build" / "StateCell.wasm")
            expect (!wasmBytes.isEmpty) "XRPL wasm extra must be nonempty"
            let note := FinalizedArtifactsV1.evidenceNoteOf finalized
            expect (note.contains "wasm32-unknown-unknown" &&
                note.contains "ContractCreate" &&
                note.contains Targets.Xrpl.FinalizeV1.xrplWasmStdGitRevV1)
              "XRPL wasm finalization evidence must name the triple, craft rev, and ContractCreate boundary"
            IO.println s!"  XRPL wasm profile: built with ambient cargo at {path}"

unsafe def testUnknownProfileFailClosed : IO Unit := do
  match CodegenProfileId.parse? "not-a-real-profile-v1" with
  | none =>
      throw <| IO.userError "not-a-real-profile-v1 must remain grammar-valid"
  | some unknown =>
      match Targets.BuildSelectionV1.resolveBuildSelectionV1
          TargetId.xrpl (some unknown) with
      | .error e =>
          expect (e.code == "PF-PROFILE-UNKNOWN")
            s!"unknown XRPL profile must be PF-PROFILE-UNKNOWN, got {e.code}: {e.render}"
      | .ok sel =>
          throw <| IO.userError
            s!"unknown XRPL profile must fail closed, got {sel.codegenProfile}"

private unsafe def expectPlanFc (label source : String) : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let parsed ← liftResult (← session.selectProgramV1
    source s!"<xrpl-{label}>" s!"Tests.Xrpl{label}" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  match planXrpl compiled with
  | .error e =>
      expect (e.code == "PF-PLAN-INVARIANT")
        s!"{label} must be a Plan invariant, got {e.code}: {e.render}"
  | .ok _ =>
      throw <| IO.userError s!"{label} must Plan fail closed"

unsafe def testInvariantFailClosed : IO Unit := do
  expectPlanFc "Invariant" <|
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program InvCell where\n" ++
    "  state count : UInt64\n" ++
    "  init() do\n" ++
    "    count := 0\n" ++
    "  entry tick() : UInt64 do\n" ++
    "    count := count + 1\n" ++
    "    return count\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n" ++
    "  invariant even : count % 2 == 0\n"

unsafe def testCallFailClosed : IO Unit := do
  expectPlanFc "Call" <|
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program CallCell where\n" ++
    "  state count : UInt64\n" ++
    "  init() do\n" ++
    "    count := 0\n" ++
    "  entry ping(s : UInt64) : UInt64 do\n" ++
    "    call Other.method(s)\n" ++
    "    count := count + 1\n" ++
    "    return count\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"

unsafe def testCryptoSha256StayFailClosed : IO Unit := do
  let cryptoBody (qn : String) : String :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program CryptoCell where\n" ++
    "  state count : UInt64\n" ++
    "  init() do\n" ++
    "    count := 0\n" ++
    "  entry hashit(s : UInt64) : UInt64 do\n" ++
    s!"    call {qn}(s)\n" ++
    "    return count\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  expectPlanFc "Sha256" (cryptoBody "pf.crypto.sha256")
  expectPlanFc "Keccak256" (cryptoBody "pf.crypto.keccak256")

unsafe def testContextReadStayFailClosed : IO Unit := do
  expectPlanFc "UnixTime" <|
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program TimeCell where\n" ++
    "  state pad : UInt64\n" ++
    "  init() do\n" ++
    "    pad := 0\n" ++
    "  entry probe() : UInt64 do\n" ++
    "    return context.unixTimeSeconds\n" ++
    "  view get() : UInt64 do\n" ++
    "    return pad\n"

unsafe def testInt64FailClosed : IO Unit := do
  expectPlanFc "Int64" <|
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program SignedCell where\n" ++
    "  state count : Int64\n" ++
    "  init(initial : Int64) do\n" ++
    "    count := initial\n" ++
    "  entry tick(delta : Int64) : Int64 do\n" ++
    "    count := count + delta\n" ++
    "    return count\n"

/-- T3 honesty pin: UInt64/Bool `Op.Constant` already inlines; do not re-lower. -/
unsafe def testConstCellInline : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program ConstCell where\n" ++
    "  const one : UInt64 := 1\n" ++
    "  const flag : Bool := true\n" ++
    "  state count : UInt64\n" ++
    "  init() do\n" ++
    "    count := one\n" ++
    "  entry tick() : UInt64 do\n" ++
    "    count := count + one\n" ++
    "    return count\n" ++
    "  view ok() : Bool do\n" ++
    "    return flag\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<xrpl-const-cell>" "Tests.XrplConstCell" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planXrpl compiled
  expect (plan.states.map (·.name) == #["count"])
    "ConstCell must keep a single count leaf"
  liftResult <| Targets.Xrpl.validatePlan plan
  let files ← liftResult <| buildXrpl compiled
  let some rsFile := files.find? (·.path == "ConstCell.rs") |
    throw <| IO.userError "xrpl: missing ConstCell.rs"
  let rs := rsFile.contents
  expect (rs.contains "checked_add(1")
    "ConstCell must inline the UInt64 constant as a UInt64 literal"
  expect (rs.contains "true")
    "ConstCell must inline the Bool constant"

/-- T3: Bytes 4 → 4 UInt64 low-8 leaves (`b_0`…`b_3`). -/
unsafe def testBytesBoxFlatten : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program BytesBox where\n" ++
    "  state b : Bytes 4\n" ++
    "  init() do\n" ++
    "    b[0] := 0\n" ++
    "  entry set0(v : UInt64) : UInt64 do\n" ++
    "    b[0] := 0\n" ++
    "    return v\n" ++
    "  view get0() : UInt64 do\n" ++
    "    return 0\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<xrpl-bytes-box>" "Tests.XrplBytesBox" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planXrpl compiled
  expect (plan.states.map (·.name) == #["b_0", "b_1", "b_2", "b_3"])
    "Bytes 4 must flatten to b_0..b_3 UInt64 leaves"
  liftResult <| Targets.Xrpl.validatePlan plan
  let files ← liftResult <| buildXrpl compiled
  let some rsFile := files.find? (·.path == "BytesBox.rs") |
    throw <| IO.userError "xrpl: missing BytesBox.rs"
  let rs := rsFile.contents
  expect (rs.contains "const b_0_KEY: &str = \"b_0\";")
    "BytesBox must bind b_0_KEY"
  expect (rs.contains "const b_1_KEY: &str = \"b_1\";")
    "BytesBox must bind b_1_KEY"
  expect (rs.contains "const b_2_KEY: &str = \"b_2\";")
    "BytesBox must bind b_2_KEY"
  expect (rs.contains "const b_3_KEY: &str = \"b_3\";")
    "BytesBox must bind b_3_KEY"

unsafe def testBytesN0FailClosed : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program BytesZero where\n" ++
    "  state b : Bytes 0\n" ++
    "  init() do\n" ++
    "    return\n" ++
    "  entry tick() : UInt64 do\n" ++
    "    return 0\n"
  let parsed ←
    match ← session.selectProgramV1
        source "<xrpl-BytesZero>" "Tests.XrplBytesZero" none with
    | .ok p => pure (some p)
    | .error _ => pure none
  match parsed with
  | none => pure ()
  | some parsed =>
      match Compiler.compileValidatedSourceV1 parsed with
      | .error _ => pure ()
      | .ok compiled =>
          match planXrpl compiled with
          | .error e =>
              expect (e.code == "PF-PLAN-INVARIANT")
                s!"BytesZero must be a Plan invariant, got {e.code}: {e.render}"
          | .ok _ =>
              throw <| IO.userError "BytesZero must fail closed"

unsafe def testBytesN9FailClosed : IO Unit := do
  expectPlanFc "BytesNine" <|
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program BytesNine where\n" ++
    "  state b : Bytes 9\n" ++
    "  init() do\n" ++
    "    b[0] := 0\n" ++
    "  entry set0(v : UInt64) : UInt64 do\n" ++
    "    b[0] := 0\n" ++
    "    return v\n"

/-- T4: Principal → 9 UInt64 identity leaves. Return / AccountID alias stay FC. -/
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
    source "<xrpl-principal>" "Tests.XrplPrincipal" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planXrpl compiled
  expect (plan.states.map (·.name) ==
      #["owner_len", "owner_w0", "owner_w1", "owner_w2", "owner_w3",
        "owner_w4", "owner_w5", "owner_w6", "owner_w7"])
    "Principal must flatten to owner_len + owner_w0..w7"
  liftResult <| Targets.Xrpl.validatePlan plan
  let files ← liftResult <| buildXrpl compiled
  let some rsFile := files.find? (·.path == "PrincipalMix.rs") |
    throw <| IO.userError "xrpl: missing PrincipalMix.rs"
  let rs := rsFile.contents
  expect (rs.contains "const owner_len_KEY: &str = \"owner_len\";")
    "PrincipalMix must bind owner_len_KEY"
  expect (rs.contains "who_len: u64")
    "Principal param must flatten to u64 leaves"
  expect (!rs.contains "AccountID")
    "Principal must not be aliased to XRPL AccountID"

/-- T5: named Struct flattens to p_x / p_y. Return stays FC. -/
unsafe def testPointBoxFlatten : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program PointBox where\n" ++
    "  struct Point where\n" ++
    "    x : UInt64\n" ++
    "    y : UInt64\n" ++
    "  state p : Point\n" ++
    "  init() do\n" ++
    "    p := Point.new(0, 0)\n" ++
    "  entry setX(v : UInt64) : UInt64 do\n" ++
    "    p.x := v\n" ++
    "    return p.x\n" ++
    "  view getX() : UInt64 do\n" ++
    "    return p.x\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<xrpl-point-box>" "Tests.XrplPointBox" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planXrpl compiled
  expect (plan.states.map (·.name) == #["p_x", "p_y"])
    "PointBox must flatten to p_x/p_y Plan leaves"
  liftResult <| Targets.Xrpl.validatePlan plan
  let files ← liftResult <| buildXrpl compiled
  let some rsFile := files.find? (·.path == "PointBox.rs") |
    throw <| IO.userError "xrpl: missing PointBox.rs"
  expect (rsFile.contents.contains "const p_x_KEY: &str = \"p_x\";")
    "PointBox must bind p_x_KEY"
  expect (rsFile.contents.contains "const p_y_KEY: &str = \"p_y\";")
    "PointBox must bind p_y_KEY"

unsafe def testMaybeMarkFlatten : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program MaybeMark where\n" ++
    "  enum Maybe where\n" ++
    "    | None\n" ++
    "    | Some(UInt64)\n" ++
    "  state m : Maybe\n" ++
    "  init() do\n" ++
    "    m := Maybe.None()\n" ++
    "  entry put(v : UInt64) : UInt64 do\n" ++
    "    m := Maybe.Some(v)\n" ++
    "    return v\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<xrpl-maybe-mark>" "Tests.XrplMaybeMark" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planXrpl compiled
  expect (plan.states.map (·.name) == #["m_tag", "m_p0"])
    "MaybeMark must flatten to m_tag/m_p0 Plan leaves"
  liftResult <| Targets.Xrpl.validatePlan plan

/-- T6: view-only named Struct returns flattened `(u64, u64)`. -/
unsafe def testPointViewRet : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program PointViewRet where\n" ++
    "  struct Point where\n" ++
    "    x : UInt64\n" ++
    "    y : UInt64\n" ++
    "  state p : Point\n" ++
    "  init() do\n" ++
    "    p := Point.new(0, 0)\n" ++
    "  entry ping() : UInt64 do\n" ++
    "    return 0\n" ++
    "  view getPoint() : Point do\n" ++
    "    return p\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<xrpl-point-view-ret>" "Tests.XrplPointViewRet" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planXrpl compiled
  let some v := plan.views[0]? |
    throw <| IO.userError "PointViewRet must emit a view"
  expect (v.resultKind == .aggregate 2)
    s!"PointViewRet view must be aggregate 2, got {repr v.resultKind}"
  expect (v.leaves.size == 2) "PointViewRet must carry two field leaves"
  liftResult <| Targets.Xrpl.validatePlan plan
  let files ← liftResult <| buildXrpl compiled
  let some rsFile := files.find? (·.path == "PointViewRet.rs") |
    throw <| IO.userError "xrpl: missing PointViewRet.rs"
  expect (rsFile.contents.contains "-> (u64, u64)")
    "PointViewRet must emit a Rust (u64, u64) view"
  expect (rsFile.contents.contains "p_x_cur")
    "PointViewRet tuple must read p_x"
  expect (rsFile.contents.contains "p_y_cur")
    "PointViewRet tuple must read p_y"

/-- T7: entry named Struct returns the same `(u64, u64)` tuple ABI. -/
unsafe def testPointEntryRet : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program PointEntryRet where\n" ++
    "  struct Point where\n" ++
    "    x : UInt64\n" ++
    "    y : UInt64\n" ++
    "  state p : Point\n" ++
    "  init() do\n" ++
    "    p := Point.new(0, 0)\n" ++
    "  entry peek() : Point do\n" ++
    "    return p\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<xrpl-point-entry-ret>" "Tests.XrplPointEntryRet" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planXrpl compiled
  let some e := plan.entries[0]? |
    throw <| IO.userError "PointEntryRet must emit an entry"
  expect (e.resultKind == .aggregate 2)
    s!"PointEntryRet entry must be aggregate 2, got {repr e.resultKind}"
  expect (e.resultLeaves.size == 2) "PointEntryRet must carry two field leaves"
  liftResult <| Targets.Xrpl.validatePlan plan
  let files ← liftResult <| buildXrpl compiled
  let some rsFile := files.find? (·.path == "PointEntryRet.rs") |
    throw <| IO.userError "xrpl: missing PointEntryRet.rs"
  expect (rsFile.contents.contains "-> (u64, u64)")
    "PointEntryRet must emit a Rust (u64, u64) entry"
  expect (rsFile.contents.contains "p_x_cur")
    "PointEntryRet tuple must read p_x"
  expect (rsFile.contents.contains "p_y_cur")
    "PointEntryRet tuple must read p_y"

unsafe def testPrincipalReturnFailClosed : IO Unit := do
  expectPlanFc "PrincipalRet" <|
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program PrincipalReturn where\n" ++
    "  state owner : Principal\n" ++
    "  init(initial : Principal) do\n" ++
    "    owner := initial\n" ++
    "  entry ping() : UInt64 do\n" ++
    "    return 0\n" ++
    "  view getOwner() : Principal do\n" ++
    "    return owner\n"

/-- T8b: Bytes N view flattens to `(u64, …)`; entry Bytes stays FC. -/
unsafe def testBytesViewRet : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program BytesViewRet where\n" ++
    "  state b : Bytes 4\n" ++
    "  init() do\n" ++
    "    b[0] := 0\n" ++
    "  entry ping() : UInt64 do\n" ++
    "    return 0\n" ++
    "  view get() : Bytes 4 do\n" ++
    "    return b\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<xrpl-bytes-view-ret>" "Tests.XrplBytesViewRet" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planXrpl compiled
  let some v := plan.views[0]? |
    throw <| IO.userError "BytesViewRet must emit a view"
  expect (v.resultKind == .aggregate 4)
    s!"BytesViewRet view must be aggregate 4, got {repr v.resultKind}"
  expect (v.leaves.size == 4) "BytesViewRet must carry four byte leaves"
  liftResult <| Targets.Xrpl.validatePlan plan
  let files ← liftResult <| buildXrpl compiled
  let some rsFile := files.find? (·.path == "BytesViewRet.rs") |
    throw <| IO.userError "xrpl: missing BytesViewRet.rs"
  expect (rsFile.contents.contains "-> (u64, u64, u64, u64)")
    "BytesViewRet must emit a Rust 4-leaf view tuple"

unsafe def testBytesEntryReturnFailClosed : IO Unit := do
  expectPlanFc "BytesEntryRet" <|
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program BytesEntryRet where\n" ++
    "  state b : Bytes 4\n" ++
    "  init() do\n" ++
    "    b[0] := 0\n" ++
    "  entry peek() : Bytes 4 do\n" ++
    "    return b\n"

/-- T9a: if-diamond lowers to `ifThenElse` + arm stores. -/
unsafe def testIfFlow : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program IfFlow where\n" ++
    "  state count : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry bump(delta : UInt64) : UInt64 do\n" ++
    "    if count > 0 then\n" ++
    "      count := count + delta\n" ++
    "    else\n" ++
    "      count := delta\n" ++
    "    return count\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<xrpl-if-flow>" "Tests.XrplIfFlow" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planXrpl compiled
  let some bump := plan.entries.find? (·.name == "bump") |
    throw <| IO.userError "IfFlow: missing bump"
  expect (bump.stores.isEmpty && bump.result?.isNone)
    "IfFlow bump must use CFG body, not flat stores/result?"
  expect (bump.body == #[
      .ifThenElse (.compare .gt (.stateLoad 0) (.litU64 0))
        #[.store 0 (.arith .add (.stateLoad 0) (.param 0))]
        #[.store 0 (.param 0)],
      .returnValue (.stateLoad 0)])
    s!"IfFlow bump shape mismatch: {repr bump.body}"
  liftResult <| Targets.Xrpl.validatePlan plan
  let files ← liftResult <| buildXrpl compiled
  let some rsFile := files.find? (·.path == "IfFlow.rs") |
    throw <| IO.userError "xrpl: missing IfFlow.rs"
  expect (rsFile.contents.contains "if (count_cur > 0u64)")
    "IfFlow must emit a plain Rust if"

/-- T9b: integer match lowers to `switchOn`. -/
unsafe def testBranchFlow : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program BranchFlow where\n" ++
    "  state count : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry apply(choice : UInt64) : UInt64 do\n" ++
    "    match choice with\n" ++
    "    | 0 => do\n" ++
    "      return count\n" ++
    "    | 1 => do\n" ++
    "      count := count + 1\n" ++
    "    | other => do\n" ++
    "      count := other\n" ++
    "    return count\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<xrpl-branch-flow>" "Tests.XrplBranchFlow" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planXrpl compiled
  let some apply := plan.entries.find? (·.name == "apply") |
    throw <| IO.userError "BranchFlow: missing apply"
  let hasSwitch :=
    apply.body.any fun s =>
      match s with
      | .switchOn _ cases _ =>
          cases.any (fun (v, _) => v == 0) && cases.any (fun (v, _) => v == 1)
      | _ => false
  expect hasSwitch "BranchFlow apply must lower match to switchOn"
  liftResult <| Targets.Xrpl.validatePlan plan

/-- T9c: bounded-for lowers to counted `forLoop` trap, not `while true`. -/
unsafe def testLoopSum : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program LoopSum where\n" ++
    "  state count : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry addUp(n : UInt64) : UInt64 do\n" ++
    "    let limit : UInt64 := n + 4\n" ++
    "    for i in n ..< limit bounded 8 do\n" ++
    "      count := count + i\n" ++
    "    return count\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<xrpl-loop-sum>" "Tests.XrplLoopSum" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planXrpl compiled
  let some addUp := plan.entries.find? (·.name == "addUp") |
    throw <| IO.userError "LoopSum: missing addUp"
  let hasFor :=
    addUp.body.any fun s =>
      match s with
      | .forLoop _ _ _ _ maxIt _ => maxIt == 8
      | _ => false
  expect hasFor "LoopSum addUp must lower bounded-for to forLoop max=8"
  liftResult <| Targets.Xrpl.validatePlan plan
  let files ← liftResult <| buildXrpl compiled
  let some rsFile := files.find? (·.path == "LoopSum.rs") |
    throw <| IO.userError "xrpl: missing LoopSum.rs"
  expect (rsFile.contents.contains "loop {" &&
      rsFile.contents.contains "return Err(1i32)" &&
      !rsFile.contents.contains "while true")
    "LoopSum must render a counted loop trap, not an unbounded while"

/-- T5-Option: anonymous Option UInt64 flattens to tag+p0; none/some store-then-read. -/
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
    "    return v\n" ++
    "  view getOrZero() : UInt64 do\n" ++
    "    match o with\n" ++
    "    | Option.some(v) => do\n" ++
    "      return v\n" ++
    "    | _ => do\n" ++
    "      return 0\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<xrpl-opt-box>" "Tests.XrplOptBox" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planXrpl compiled
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
  liftResult <| Targets.Xrpl.validatePlan plan
  let files ← liftResult <| buildXrpl compiled
  let some rsFile := files.find? (fun f => f.path == "OptBox.rs") |
    throw <| IO.userError "xrpl: missing OptBox.rs"
  let rs := rsFile.contents
  expect (rs.contains "const o_tag_KEY: &str = \"o_tag\";")
    "OptBox.rs must bind o_tag_KEY"
  expect (rs.contains "const o_p0_KEY: &str = \"o_p0\";")
    "OptBox.rs must bind o_p0_KEY"
  expect (!rs.contains "Vec<")
    "Option flatten must not emit a Rust Vec"
  expect (!rs.contains "Option<")
    "Option flatten must not emit a Rust Option type"

unsafe def testOptionParamFailClosed : IO Unit := do
  expectPlanFc "OptParam" <|
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program OptParam where\n" ++
    "  state pad : UInt64\n" ++
    "  init() do\n" ++
    "    pad := 0\n" ++
    "  entry set(o : Option UInt64) : UInt64 do\n" ++
    "    return pad\n"

unsafe def testOptionBoolPayloadFailClosed : IO Unit := do
  expectPlanFc "OptBool" <|
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program OptBool where\n" ++
    "  state o : Option Bool\n" ++
    "  init() do\n" ++
    "    o := Option.none()\n" ++
    "  entry setSome() : UInt64 do\n" ++
    "    o := Option.some(true)\n" ++
    "    return 1\n"

/-- T8a-Map: dense cap-8 = 24 leaves; empty + upsert; miss→none via IndexGet. -/
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
    "    return v\n" ++
    "  view get(k : UInt64) : UInt64 do\n" ++
    "    match m[k] with\n" ++
    "    | Option.some(v) => do\n" ++
    "      return v\n" ++
    "    | _ => do\n" ++
    "      return 0\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<xrpl-map-mini>" "Tests.XrplMapMini" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planXrpl compiled
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
    "MapMini put must check cap-8 overflow (9th insert fail closed)"
  liftResult <| Targets.Xrpl.validatePlan plan
  let files ← liftResult <| buildXrpl compiled
  let some rsFile := files.find? (fun f => f.path == "MapMini.rs") |
    throw <| IO.userError "xrpl: missing MapMini.rs"
  let rs := rsFile.contents
  expect (rs.contains "const m_0_KEY: &str = \"m_0\";")
    "MapMini.rs must bind m_0_KEY"
  expect (rs.contains "const m_23_KEY: &str = \"m_23\";")
    "MapMini.rs must bind m_23_KEY"
  expect (rs.contains "if " && rs.contains " else ")
    "Map mux must render Rust if/else expressions"
  expect (!rs.contains "Vec<")
    "Map flatten must not emit a Rust Vec"
  expect (!rs.contains "HashMap")
    "Map flatten must not emit a Rust HashMap"

unsafe def testMapReturnFailClosed : IO Unit := do
  expectPlanFc "MapRet" <|
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program MapRet where\n" ++
    "  state m : Map UInt64 UInt64\n" ++
    "  init() do\n" ++
    "    m := Map.empty()\n" ++
    "  entry peek() : Map UInt64 UInt64 do\n" ++
    "    return m\n"

unsafe def testMapParamFailClosed : IO Unit := do
  expectPlanFc "MapParam" <|
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program MapParam where\n" ++
    "  state pad : UInt64\n" ++
    "  init() do\n" ++
    "    pad := 0\n" ++
    "  entry put(m : Map UInt64 UInt64) : UInt64 do\n" ++
    "    return pad\n"

unsafe def run : IO Unit := do
  testStateCellXrplSource
  testMaterializeDeterminism
  testSelectionBindsDefaultSourceProfile
  testWasmProfileSelection
  testWasmProfileFinalize
  testUnknownProfileFailClosed
  testInvariantFailClosed
  testCallFailClosed
  testCryptoSha256StayFailClosed
  testContextReadStayFailClosed
  testInt64FailClosed
  testConstCellInline
  testBytesBoxFlatten
  testBytesN0FailClosed
  testBytesN9FailClosed
  testBytesViewRet
  testBytesEntryReturnFailClosed
  testPrincipalIdentityLeaves
  testPrincipalReturnFailClosed
  testPointBoxFlatten
  testMaybeMarkFlatten
  testPointViewRet
  testPointEntryRet
  testIfFlow
  testBranchFlow
  testLoopSum
  testOptBoxAdmit
  testOptionParamFailClosed
  testOptionBoolPayloadFailClosed
  testMapMiniAdmit
  testMapReturnFailClosed
  testMapParamFailClosed

end Tests.Materialization.XrplPlanV1
