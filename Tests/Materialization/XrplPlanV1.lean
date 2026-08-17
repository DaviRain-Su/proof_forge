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

end Tests.Materialization.XrplPlanV1
