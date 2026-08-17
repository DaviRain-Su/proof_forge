/-
  XRPL Q0 target leaf tests (ADR-0049): Plan/IR/emitter over retained
  SemanticProgramV1. Uses planFromCompiledSemanticV1 / buildFromCompiledSemanticV1
  plus the full capability/materialize/finalize product path.
-/
import ProofForgeV2.Targets.Xrpl
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

unsafe def testSelectionBindsSoleProfile : IO Unit := do
  let selection ← liftResult <|
    Targets.BuildSelectionV1.resolveBuildSelectionV1 TargetId.xrpl none
  expect (selection.codegenProfile == CodegenProfileId.xrplBedrockSourceU64V1)
    "XRPL selection must bind its sole source profile"
  expect (selection.kind == TargetKind.xrpl)
    "XRPL selection must bind TargetKind.xrpl"

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
  testSelectionBindsSoleProfile
  testUnknownProfileFailClosed
  testInvariantFailClosed
  testCallFailClosed
  testCryptoSha256StayFailClosed
  testContextReadStayFailClosed
  testInt64FailClosed

end Tests.Materialization.XrplPlanV1
