/-
  OpenVM target leaf tests (O0 ADR-0045 + O1 ADR-0046): Plan/IR/emitter over
  retained SemanticProgramV1. Uses planFromCompiledSemanticV1 /
  buildFromCompiledSemanticV1 so the suite does not require registry wiring
  for its plan-level checks, plus full capability/materialize/finalize
  product-path tests for both the default zero-tool source profile and the
  opt-in `openvm-guest-elf-v1` build profile. Main agent registers this suite.
-/
import ProofForgeV2
import ProofForgeV2.Targets.OpenVM
import ProofForgeV2.Targets.OpenVM.FinalizeV1
import Tests.Language.ParserSession
import Tests.Compiler.ValidatedSourceV1Pipeline

namespace Tests.Materialization.OpenVmGuestSourceV1

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Targets

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def liftResult (result : CompileResult α) : IO α :=
  match result with
  | .ok value => pure value
  | .error error => throw <| IO.userError error.render

private def planOpenVm (compiled : CompiledSemanticV1) :
    CompileResult Targets.OpenVM.Plan :=
  Targets.OpenVM.planFromCompiledSemanticV1 compiled

private def buildOpenVm (compiled : CompiledSemanticV1) :
    CompileResult (Array OutputFile) :=
  Targets.OpenVM.buildFromCompiledSemanticV1 compiled

/-- StateCell: plan shape + key Rust/catalog source fragments. -/
unsafe def testStateCellOpenVmSource : IO Unit := do
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
    source "<openvm-state-cell>" "Tests.OpenVmStateCell" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planOpenVm compiled
  expect (plan.states.map (·.name) == #["count"])
    "StateCell OpenVM plan must carry the count state field"
  expect (plan.entries.map (·.name) == #["increment"])
    "StateCell OpenVM plan must carry the increment entry"
  expect (plan.views.map (·.name) == #["get"])
    "StateCell OpenVM plan must carry the get view"
  expect (plan.signedNumeric == false)
    "StateCell stays unsigned u64"
  expect (plan.profile == "openvm-guest-source-v1")
    "OpenVM plan must carry the frozen profile string"
  expect (plan.vmConfig == "openvm-2.0.x-rv32im-stub-v1")
    "OpenVM plan must carry the frozen vmConfig stub"
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
  liftResult <| Targets.OpenVM.validatePlan plan
  let files ← liftResult <| buildOpenVm compiled
  expect (files.size == 4) "OpenVM must emit exactly four files"
  let some cargoFile := files.find? (·.path == "guest/Cargo.toml") |
    throw <| IO.userError "openvm: missing guest/Cargo.toml"
  expect (cargoFile.mediaType == "text/x-toml")
    "guest/Cargo.toml media type must be text/x-toml"
  expect (cargoFile.contents.contains "openvm = \"=2.0.1\"")
    "Cargo.toml must pin openvm = \"=2.0.1\""
  expect (cargoFile.contents.contains "name = \"pf-openvm-guest-StateCell\"")
    "Cargo.toml package name must derive from programName"
  let some openvmToml := files.find? (·.path == "guest/openvm.toml") |
    throw <| IO.userError "openvm: missing guest/openvm.toml"
  expect (openvmToml.mediaType == "text/x-toml")
    "guest/openvm.toml media type must be text/x-toml"
  expect (openvmToml.contents.contains "[app_vm_config.rv32i]")
    "openvm.toml must enable rv32i"
  expect (openvmToml.contents.contains "[app_vm_config.rv32m]")
    "openvm.toml must enable rv32m"
  expect (openvmToml.contents.contains "[app_vm_config.io]")
    "openvm.toml must enable io"
  let some mainRs := files.find? (·.path == "guest/src/main.rs") |
    throw <| IO.userError "openvm: missing guest/src/main.rs"
  expect (mainRs.mediaType == "text/x-rust")
    "guest/src/main.rs media type must be text/x-rust"
  let rs := mainRs.contents
  expect (rs.contains "#![no_main]") "main.rs must declare #![no_main]"
  expect (rs.contains "#![no_std]") "main.rs must declare #![no_std]"
  expect (rs.contains "openvm::entry!(main);")
    "main.rs must declare the openvm::entry! guest entry point"
  expect (rs.contains "pub struct State {")
    "main.rs must declare the State struct"
  expect (rs.contains "pub count: u64,")
    "main.rs State struct must carry the count field"
  expect (!rs.contains "i64")
    "unsigned StateCell must not force i64"
  expect (rs.contains "pub fn initialize(initial: u64) -> State {")
    "main.rs must declare initialize with the initial parameter"
  expect (rs.contains "pub fn increment(state: &mut State, delta: u64) -> Result<u64, u32> {")
    "main.rs must declare increment with &mut State and Result<u64, u32>"
  expect (rs.contains "checked_add(delta).ok_or(1u32)?")
    "main.rs increment must use checked_add with overflow code 1"
  expect (rs.contains "pub fn get(state: &State) -> u64 {")
    "main.rs must declare get with &State"
  expect (rs.contains "fn main() {")
    "main.rs must include the openvm::entry! target fn"
  expect (rs.contains "openvm::io::read();")
    "main.rs must read guest inputs via openvm::io::read"
  expect (rs.contains "openvm::io::reveal_bytes32(public_output);")
    "main.rs must reveal the packed outcome via openvm::io::reveal_bytes32"
  let some catalog := files.find? (·.path == "StateCell.openvm-guest.json") |
    throw <| IO.userError "openvm: missing StateCell.openvm-guest.json"
  expect (catalog.mediaType == "application/json")
    "catalog media type must be application/json"
  let json := catalog.contents
  expect (json.contains "\"schema\": \"proof-forge.openvm-guest.v1\"")
    "catalog must carry the exact schema id"
  expect (json.contains "\"profile\": \"openvm-guest-source-v1\"")
    "catalog must carry the exact profile"
  expect (json.contains "\"artifactKind\": \"source-only\"")
    "catalog artifactKind must be source-only"
  expect (json.contains "\"proofStatus\": \"not-produced\"")
    "catalog proofStatus must be not-produced"
  expect (json.contains "\"programName\": \"StateCell\"")
    "catalog must carry the programName"
  expect (json.contains "\"vmConfig\": \"openvm-2.0.x-rv32im-stub-v1\"")
    "catalog must carry the frozen vmConfig stub"
  expect (json.contains "\"enabledExtensions\": []")
    "catalog enabledExtensions must be empty"
  expect (json.contains "\"executableCommitment\": null")
    "catalog executableCommitment must be null"
  expect (json.contains "\"proofMode\": null")
    "catalog proofMode must be null"
  expect (json.contains "\"verifierBinding\": null")
    "catalog verifierBinding must be null"
  expect (json.contains "\"guest/Cargo.toml\"" && json.contains "\"guest/openvm.toml\"" &&
      json.contains "\"guest/src/main.rs\"")
    "catalog files must list all three guest sources"

/-- Materialize path + determinism. -/
unsafe def testMaterializeDeterminism : IO Unit := do
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
    source "<openvm-det>" "Tests.OpenVmDet" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let files1 ← liftResult <| buildOpenVm compiled
  let files2 ← liftResult <| buildOpenVm compiled
  expect (files1 == files2)
    "OpenVM materialize must be deterministic"
  let plan1 ← liftResult <| planOpenVm compiled
  let plan2 ← liftResult <| planOpenVm compiled
  expect (plan1 == plan2)
    "OpenVM plan lower must be deterministic"
  match Targets.OpenVM.engineeringOpenVmPlanDigestV1 plan1 with
  | .ok d1 =>
      match Targets.OpenVM.engineeringOpenVmPlanDigestV1 plan2 with
      | .ok d2 => expect (d1 == d2) "plan digest must be deterministic"
      | .error e => throw <| IO.userError e
  | .error e => throw <| IO.userError e

/-- Full registry/capability/materialize/finalize path for the shipped target. -/
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
    "    return count\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<openvm-capability>" "Tests.OpenVmCapability" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let selection ← liftResult <|
    Targets.BuildSelectionV1.resolveBuildSelectionV1 TargetId.openvm none
  expect (selection.codegenProfile == CodegenProfileId.openvmGuestSourceV1)
    "OpenVM selection must bind its sole source profile"
  let capability ← liftResult <|
    Targets.resolveEngineeringRequirementsV1 selection compiled
  let plan ← liftResult <| Targets.OpenVM.planFromCapability capability
  expect (plan.programName == "StateCell")
    "capability Plan must retain the compiled artifact name"
  let artifacts ← liftResult <| Targets.materializeResult capability
  expect (MaterializedArtifactsV1.targetIdOf artifacts == TargetId.openvm)
    "materialized artifacts must bind TargetId.openvm"
  let files := MaterializedArtifactsV1.filesOf artifacts
  expect (files.size == 4)
    "registry materialize must emit exactly four OpenVM guest files"
  let finalized ← Targets.finalizeMaterializedArtifactsV1
    capability artifacts (System.FilePath.mk ".")
  expect (!FinalizedArtifactsV1.deployableOf finalized)
    "OpenVM finalization must remain non-deployable"
  expect (FinalizedArtifactsV1.extraFilesOf finalized).isEmpty
    "OpenVM zero-tool finalization must add no files"
  let note := FinalizedArtifactsV1.evidenceNoteOf finalized
  expect (note.contains "openvm-transpiler" && note.contains "prove/verify")
    "OpenVM finalization evidence must state the exact zero-tool boundary"

private unsafe def elfCompiledStateCell : IO CompiledSemanticV1 := do
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
    "    return count\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<openvm-elf>" "Tests.OpenVmElf" none)
  liftResult <| Compiler.compileValidatedSourceV1 parsed

/-- ADR-0046 O1: selecting the explicit elf profile shares the exact same
    Plan/base materialize as the default source profile. -/
unsafe def testElfProfileSelection : IO Unit := do
  let compiled ← elfCompiledStateCell
  let selection ← liftResult <|
    Targets.BuildSelectionV1.resolveBuildSelectionV1
      TargetId.openvm (some CodegenProfileId.openvmGuestElfV1)
  expect (selection.codegenProfile == CodegenProfileId.openvmGuestElfV1)
    "OpenVM selection must bind the explicit elf profile when requested"
  let capability ← liftResult <|
    Targets.resolveEngineeringRequirementsV1 selection compiled
  let plan ← liftResult <| Targets.OpenVM.planFromCapability capability
  expect (plan.programName == "StateCell")
    "OpenVM elf profile must retain the compiled artifact name"
  let artifacts ← liftResult <| Targets.materializeResult capability
  expect (MaterializedArtifactsV1.codegenProfileIdOf artifacts == CodegenProfileId.openvmGuestElfV1)
    "OpenVM elf materialize must bind the elf profile"
  let files := MaterializedArtifactsV1.filesOf artifacts
  expect (files.size == 4)
    "OpenVM elf profile must emit the same four guest base files as the source profile"

/-- ADR-0046 O1 Finalize: missing `cargo-openvm` fails closed with
    `PF-TOOLCHAIN-MISSING`; when locked/ambient `cargo-openvm` is present,
    the RV32IM ELF + `.vmexe` extras are staged at the stable
    `openvm-build/*` paths. Host-optional in the success arm: `cargo-openvm`
    itself may still be present without the separate ambient
    `riscv32im-risc0-zkvm-elf` nightly guest toolchain, so a build failure
    there is an honest skip rather than a hard failure (mirrors the Noir
    nargo-assisted / Quint host-optional acceptance discipline). -/
unsafe def testElfProfileFinalize : IO Unit := do
  let compiled ← elfCompiledStateCell
  let selection ← liftResult <|
    Targets.BuildSelectionV1.resolveBuildSelectionV1
      TargetId.openvm (some CodegenProfileId.openvmGuestElfV1)
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
    let cargoOpenvm? ← Targets.OpenVM.FinalizeV1.resolveCargoOpenvmPathV1
    match cargoOpenvm? with
    | none => do
        let outcome ←
          try
            let _ ← Targets.finalizeMaterializedArtifactsV1 capability artifacts stagingDir
            pure (Except.ok () : Except String Unit)
          catch e => pure (Except.error (toString e))
        match outcome with
        | .ok () =>
            throw <| IO.userError "OpenVM elf finalize must fail without cargo-openvm"
        | .error msg =>
            expect (msg.contains "PF-TOOLCHAIN-MISSING")
              s!"missing cargo-openvm must fail closed with PF-TOOLCHAIN-MISSING, got: {msg}"
    | some path => do
        let outcome ←
          try
            let finalized ←
              Targets.finalizeMaterializedArtifactsV1 capability artifacts stagingDir
            pure (Except.ok finalized : Except String FinalizedArtifactsV1)
          catch e => pure (Except.error (toString e))
        match outcome with
        | .error msg =>
            IO.println
              s!"  skipped: ambient cargo-openvm present but guest build failed \
(missing riscv32im-risc0-zkvm-elf / nightly toolchain?): {msg}"
        | .ok finalized =>
            expect (!FinalizedArtifactsV1.deployableOf finalized)
              "OpenVM elf finalization must remain non-deployable"
            let extras := FinalizedArtifactsV1.extraFilesOf finalized
            expect (extras == #["openvm-build/StateCell", "openvm-build/StateCell.vmexe"])
              s!"OpenVM elf extras must use the stable openvm-build/* paths, got {extras}"
            let elfBytes ← IO.FS.readBinFile (stagingDir / "openvm-build" / "StateCell")
            expect (!elfBytes.isEmpty) "OpenVM elf extra must be nonempty"
            let vmexeBytes ← IO.FS.readBinFile (stagingDir / "openvm-build" / "StateCell.vmexe")
            expect (!vmexeBytes.isEmpty) "OpenVM vmexe extra must be nonempty"
            let note := FinalizedArtifactsV1.evidenceNoteOf finalized
            expect (note.contains "cargo-openvm" && note.contains "prove/verify")
              "OpenVM elf finalization evidence must name cargo-openvm and the prove/verify boundary"
            IO.println s!"  OpenVM elf profile: built with ambient cargo-openvm at {path}"

/-- Fail closed: call/schedule are outside O0. -/
unsafe def testFailClosedCall : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program OracleCall where\n" ++
    "  state count : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry bump(x : UInt64) : UInt64 do\n" ++
    "    call Oracle.feed(x)\n" ++
    "    count := count + x\n" ++
    "    return count\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<openvm-call>" "Tests.OpenVmCall" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  match planOpenVm compiled with
  | .error (.planInvariant .openvm msg) =>
      expect (msg.contains "call/schedule are outside O0")
        s!"generic call Plan FC must contain 'call/schedule are outside O0', got: {msg}"
  | .error e => throw <| IO.userError s!"expected planInvariant .openvm, got {e.render}"
  | .ok _ => throw <| IO.userError "call must fail closed at OpenVM plan"

/-- SYS-S5: OpenVM has no sha256/keccak256 host. Exact `pf.crypto.*` stays
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
      source s!"<openvm-{label}>" s!"Tests.OpenVm{label}" none)
    let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
    match planOpenVm compiled with
    | .error e =>
        expect (e.render.contains needle)
          s!"{label} Plan FC must contain '{needle}', got: {e.render}"
        unless also.isEmpty do
          expect (e.render.contains also)
            s!"{label} Plan FC must contain '{also}', got: {e.render}"
    | .ok _ =>
        throw <| IO.userError
          s!"{label} must Plan fail closed (no OpenVM crypto host)"
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
  expectPlanFc "Sha256OpenVm" (cryptoBody "pf.crypto.sha256")
    "has no OpenVM host binding"
  expectPlanFc "Keccak256OpenVm" (cryptoBody "pf.crypto.keccak256")
    "has no OpenVM host binding"
  expectPlanFc "Sha256OpenVmHashNoPad" (cryptoBody "pf.crypto.hashNoPad")
    "has no OpenVM host binding"
  expectPlanFc "EcdsaRecoverOpenVm"
    (cryptoBody "pf.crypto.ecdsaRecoverSecp256k1")
    "has no OpenVM host binding" "ecdsaRecoverSecp256k1"

/-- SYS-S4: OpenVM has no unixTime/blockHeight/attachedValue/chainId host.
    Named UInt64 ContextRead keys stay Plan fail closed. caller/self are
    Principal and stay on the generic ContextRead envelope (O0 rejects
    Principal at type closure first). -/
unsafe def testContextReadStayFailClosed : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let expectPlanFc (label body needle schemaId : String) : IO Unit := do
    let source :=
      "import ProofForgeV2\n" ++
      "open ProofForgeV2.Language\n" ++
      s!"program {label} where\n" ++ body
    let parsed ← liftResult (← session.selectProgramV1
      source s!"<openvm-{label}>" s!"Tests.OpenVm{label}" none)
    let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
    match planOpenVm compiled with
    | .error e =>
        expect (e.render.contains needle)
          s!"{label} Plan FC must contain '{needle}', got: {e.render}"
        expect (e.render.contains schemaId)
          s!"{label} Plan FC must name '{schemaId}', got: {e.render}"
    | .ok _ =>
        throw <| IO.userError
          s!"{label} must Plan fail closed (no OpenVM context host)"
  let ctxBody (place : String) : String :=
    "  state pad : UInt64\n" ++
      "  init() do\n" ++
      "    pad := 0\n" ++
      "  entry probe() : UInt64 do\n" ++
      "    return " ++ place ++ "\n" ++
      "  view get() : UInt64 do\n" ++
      "    return pad\n"
  expectPlanFc "UnixTimeOpenVm" (ctxBody "context.unixTimeSeconds")
    "has no OpenVM host binding" "proof-forge.context.unix-time-seconds.v1"
  expectPlanFc "BlockHeightOpenVm" (ctxBody "context.blockHeight")
    "has no OpenVM host binding" "proof-forge.context.block-height.v1"
  expectPlanFc "AttachedValueOpenVm" (ctxBody "context.attachedValue")
    "has no OpenVM host binding" "proof-forge.context.attached-value.v1"
  expectPlanFc "ChainIdOpenVm" (ctxBody "context.chainId")
    "has no OpenVM host binding" "proof-forge.context.chain-id.v1"

/-- SYS-E2: OpenVM has no native vault host. `pf.assets.native.balanceOfSelf`
    stays Plan fail closed. token/U128 stay on the generic envRead envelope
    (Principal mint / UInt128 rejected first). -/
unsafe def testEnvReadNativeStayFailClosed : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program EnvReadBalanceOpenVm where\n" ++
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
    source "<openvm-env-read-native>" "Tests.EnvReadBalanceOpenVm" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  match planOpenVm compiled with
  | .error e =>
      expect (e.render.contains "has no OpenVM host binding")
        s!"EnvReadBalanceOpenVm Plan FC must contain 'has no OpenVM host binding', got: {e.render}"
      expect (e.render.contains "envRead" || e.render.contains "nativeVaultBalance")
        s!"EnvReadBalanceOpenVm Plan FC must name envRead/nativeVaultBalance, got: {e.render}"
  | .ok _ =>
      throw <| IO.userError
        "EnvReadBalanceOpenVm must Plan fail closed (no OpenVM vault host)"

/-- Fail closed: emit is outside O0 (no event surface). -/
unsafe def testFailClosedEmit : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program Ev where\n" ++
    "  event Ticked(v : UInt64)\n" ++
    "  entry tick(x : UInt64) : UInt64 do\n" ++
    "    emit Ticked(x)\n" ++
    "    return x\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<openvm-emit>" "Tests.OpenVmEmit" none)
  match Compiler.compileValidatedSourceV1 parsed with
  | .error _ => pure ()
  | .ok compiled =>
      let selection ← liftResult <|
        Targets.BuildSelectionV1.resolveBuildSelectionV1 TargetId.openvm none
      match Targets.resolveEngineeringRequirementsV1 selection compiled with
      | .error (.unsupportedRequirementV1 msg) =>
          expect (msg.contains "effect.event")
            s!"event resolver failure must name effect.event, got: {msg}"
      | .error e =>
          throw <| IO.userError s!"expected unsupportedRequirementV1, got {e.render}"
      | .ok _ => throw <| IO.userError "event must fail at OpenVM capability resolution"
      match planOpenVm compiled with
      | .error (.planInvariant .openvm msg) =>
          expect (msg.contains "event" || msg.contains "events" ||
              msg.contains "outside O0" || msg.contains "empty")
            s!"emit must fail closed, got: {msg}"
      | .error e => throw <| IO.userError s!"expected planInvariant .openvm, got {e.render}"
      | .ok _ => throw <| IO.userError "emit must fail closed at OpenVM plan"

/-- Fail closed: invariants are outside O0. -/
unsafe def testFailClosedInvariant : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program Logic where\n" ++
    "  state count : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry check() : Bool do\n" ++
    "    return count >= 0\n" ++
    "  invariant nonNeg : count >= 0\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<openvm-invariant>" "Tests.OpenVmInvariant" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  match planOpenVm compiled with
  | .error (.planInvariant .openvm msg) =>
      expect (msg.contains "invariant" || msg.contains "outside O0")
        s!"invariant must fail closed, got: {msg}"
  | .error e => throw <| IO.userError s!"expected planInvariant .openvm, got {e.render}"
  | .ok _ => throw <| IO.userError "invariant must fail closed at OpenVM plan"

/-- Fail closed: pf.assets extension is outside O0. -/
unsafe def testFailClosedPfAssets : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let pfAssetsDigestV1 : String :=
    "sha256:59412f732e634b0256a02c9ec23a253c38478879d6b74b279e750b220879aaa9"
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program Tip where\n" ++
    "  requires extension pf.assets version \"1.1.0\"\n" ++
    "    digest \"" ++ pfAssetsDigestV1 ++ "\"\n" ++
    "  entry tip(dst : Principal, amount : UInt64) : UInt64 do\n" ++
    "    call pf.assets.native.deposit(amount)\n" ++
    "    return amount\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<openvm-pf-assets>" "Tests.OpenVmPfAssets" none)
  match Compiler.compileValidatedSourceV1 parsed with
  | .error _ => pure ()
  | .ok compiled =>
      let selection ← liftResult <|
        Targets.BuildSelectionV1.resolveBuildSelectionV1 TargetId.openvm none
      match Targets.resolveEngineeringRequirementsV1 selection compiled with
      | .error (.unsupportedRequirementV1 msg) =>
          expect (msg.contains "extension.pf-assets" ||
              msg.contains "effect.synchronous-call")
            s!"pf.assets resolver failure must cite the declined key, got: {msg}"
      | .error e =>
          throw <| IO.userError s!"expected unsupportedRequirementV1, got {e.render}"
      | .ok _ => throw <| IO.userError "pf.assets must fail at OpenVM capability resolution"

/-- T4: Principal identity storage flattens to 9 UInt64 leaves. Return stays FC. -/
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
    source "<openvm-principal>" "Tests.OpenVmPrincipal" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planOpenVm compiled
  expect (!plan.signedNumeric) "PrincipalMix stays unsigned"
  expect (plan.states.map (·.name) ==
      #["owner_len", "owner_w0", "owner_w1", "owner_w2", "owner_w3",
        "owner_w4", "owner_w5", "owner_w6", "owner_w7"])
    "Principal must flatten to owner_len + owner_w0..w7"
  liftResult <| Targets.OpenVM.validatePlan plan
  let files ← liftResult <| buildOpenVm compiled
  expect (!files.isEmpty) "PrincipalMix must materialize OpenVM files"
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
    retSource "<openvm-principal-ret>" "Tests.OpenVmPrincipalReturn" none)
  let compiledRet ← liftResult <| Compiler.compileValidatedSourceV1 parsedRet
  match planOpenVm compiledRet with
  | .ok _ => throw <| IO.userError "Principal return must fail closed"
  | .error e =>
      expect (e.render.contains "Principal")
        s!"Principal return must cite Principal, got {e.render}"

/-- Homogeneous UInt64 mul/div/mod emit checked Rust ops. -/
unsafe def testMulDivModAdmit : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program Scale where\n" ++
    "  state count : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry scale(factor : UInt64) : UInt64 do\n" ++
    "    count := count * factor / 3 + count % 3\n" ++
    "    return count\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<openvm-scale>" "Tests.OpenVmScale" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planOpenVm compiled
  expect (!plan.signedNumeric) "Scale stays unsigned"
  liftResult <| Targets.OpenVM.validatePlan plan
  let files ← liftResult <| buildOpenVm compiled
  let some rs := files.find? (·.path == "guest/src/main.rs") |
    throw <| IO.userError "openvm: missing guest/src/main.rs"
  expect (rs.contents.contains "checked_mul" &&
      rs.contents.contains "checked_div" &&
      rs.contents.contains "checked_rem")
    "Scale guest must emit checked_mul/div/rem"

/-- Signed Int64 mul is admitted via i64::checked_mul. -/
unsafe def testSignedMulAdmit : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program I64Mul where\n" ++
    "  state n : Int64\n" ++
    "  init(initial : Int64) do\n" ++
    "    n := initial\n" ++
    "  entry scale(factor : Int64) : Int64 do\n" ++
    "    n := n * factor\n" ++
    "    return n\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<openvm-i64-mul>" "Tests.OpenVmI64Mul" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planOpenVm compiled
  expect plan.signedNumeric "I64Mul is signed"
  liftResult <| Targets.OpenVM.validatePlan plan
  let files ← liftResult <| buildOpenVm compiled
  let some rs := files.find? (·.path == "guest/src/main.rs") |
    throw <| IO.userError "openvm: missing guest/src/main.rs"
  expect (rs.contents.contains "checked_mul")
    "signed mul guest must emit checked_mul"

/-- Bitwise NOT stays outside O0. -/
unsafe def testFailClosedBitNot : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program Mask where\n" ++
    "  entry mask(value : UInt64) : UInt64 do\n" ++
    "    return ~value\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<openvm-bitnot>" "Tests.OpenVmBitNot" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  match planOpenVm compiled with
  | .error (.planInvariant .openvm msg) =>
      expect (msg.contains "bitNot" || msg.contains "unary")
        s!"bitNot must fail closed, got: {msg}"
  | .error e => throw <| IO.userError s!"expected planInvariant .openvm, got {e.render}"
  | .ok _ => throw <| IO.userError "bitNot must fail closed at OpenVM plan"

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
    "  entry scan(n : UInt64) : UInt64 do\n" ++
    "    for i in n ..< n bounded 2 do\n" ++
    "      count := count + 1\n" ++
    "    return count\n" ++
    "  entry addUpTight(n : UInt64) : UInt64 do\n" ++
    "    for i in n ..< n + 4 bounded 3 do\n" ++
    "      count := count + i\n" ++
    "    return count\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<openvm-loop-sum>" "Tests.OpenVmLoopSum" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planOpenVm compiled
  let some addUp := plan.entries.find? (·.name == "addUp") |
    throw <| IO.userError "LoopSum: missing addUp"
  let hasFor :=
    addUp.body.any fun s =>
      match s with
      | .forLoop _ _ _ _ maxIt _ => maxIt == 8
      | _ => false
  expect hasFor "LoopSum addUp must lower bounded-for to forLoop max=8"
  liftResult <| Targets.OpenVM.validatePlan plan
  let files ← liftResult <| buildOpenVm compiled
  let some rsFile := files.find? (·.path == "guest/src/main.rs") |
    throw <| IO.userError "LoopSum: missing guest/src/main.rs"
  expect (rsFile.contents.contains "loop {" &&
      rsFile.contents.contains "return Err(1u32)" &&
      !rsFile.contents.contains "while true")
    "LoopSum guest must render a counted loop trap, not an unbounded while"
  IO.println "  ✓ LoopSum bounded-for"

unsafe def testBranchFlow : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program BranchFlow where\n" ++
    "  state count : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry bump(delta : UInt64) : UInt64 do\n" ++
    "    if count > 0 then\n" ++
    "      count := count + delta\n" ++
    "    else\n" ++
    "      count := delta\n" ++
    "    return count\n" ++
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
    source "<openvm-branch-flow>" "Tests.OpenVmBranchFlow" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planOpenVm compiled
  let some apply := plan.entries.find? (·.name == "apply") |
    throw <| IO.userError "BranchFlow: missing apply"
  let hasSwitch :=
    apply.body.any fun s =>
      match s with
      | .switchOn _ cases _ =>
          cases.any (fun (v, _) => v == 0) && cases.any (fun (v, _) => v == 1)
      | _ => false
  expect hasSwitch "BranchFlow apply must lower match to switchOn"
  liftResult <| Targets.OpenVM.validatePlan plan
  IO.println "  ✓ BranchFlow if + integer match"

unsafe def testMaybeMatch : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program MaybeMatch where\n" ++
    "  state slot : Option UInt64\n" ++
    "  init() do\n" ++
    "    slot := Option.none()\n" ++
    "  entry take() : UInt64 do\n" ++
    "    match slot with\n" ++
    "    | Option.some(x) => do\n" ++
    "      return x\n" ++
    "    | _ => do\n" ++
    "      return 0\n" ++
    "  view peek() : UInt64 do\n" ++
    "    return 0\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<openvm-maybe-match>" "Tests.OpenVmMaybeMatch" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planOpenVm compiled
  let some take := plan.entries.find? (·.name == "take") |
    throw <| IO.userError "MaybeMatch: missing take"
  let hasSwitch :=
    take.body.any fun s =>
      match s with
      | .switchOn _ cases _ =>
          cases.any (fun (v, _) => v == 0) || cases.any (fun (v, _) => v == 1)
      | _ => false
  expect hasSwitch "MaybeMatch take must switch on the Option tag leaf"
  liftResult <| Targets.OpenVM.validatePlan plan
  IO.println "  ✓ MaybeMatch Option tag switch"

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
    source "<openvm-if-flow>" "Tests.OpenVmIfFlow" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planOpenVm compiled
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
  liftResult <| Targets.OpenVM.validatePlan plan
  IO.println "  ✓ IfFlow if-diamond"

/-- T3: scalar const inlines as a guest u64 literal (no second evaluator). -/
unsafe def testFailClosedConstant : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program ConstUse where\n" ++
    "  const base : UInt64 := 1\n" ++
    "  entry get() : UInt64 do\n" ++
    "    return base\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<openvm-const>" "Tests.OpenVmConst" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planOpenVm compiled
  liftResult <| Targets.OpenVM.validatePlan plan
  let files ← liftResult <| buildOpenVm compiled
  let some mainRs := files.find? (·.path == "guest/src/main.rs") |
    throw <| IO.userError "openvm: missing guest/src/main.rs"
  expect (mainRs.contents.contains "1")
    "ConstUse must inline the UInt64 constant as a guest literal"

/-- Fail closed: private state. -/
unsafe def testFailClosedPrivateState : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program Priv where\n" ++
    "  state private secret : UInt64\n" ++
    "  init() do\n" ++
    "    secret := 0\n" ++
    "  entry get() : UInt64 do\n" ++
    "    return secret\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<openvm-priv>" "Tests.OpenVmPriv" none)
  match Compiler.compileValidatedSourceV1 parsed with
  | .error _ => pure ()
  | .ok compiled =>
      match planOpenVm compiled with
      | .error (.planInvariant .openvm msg) =>
          expect (msg.contains "public" || msg.contains "UInt64" ||
              msg.contains "private" || msg.contains "visibility")
            s!"private state must fail closed, got: {msg}"
      | .error e => throw <| IO.userError s!"expected planInvariant .openvm, got {e.render}"
      | .ok _ => throw <| IO.userError "private state must fail closed at OpenVM plan"

/-- Homogeneous Int64: guest `i64` + Rust `i64::checked_add`. -/
unsafe def testInt64Cell : IO Unit := do
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
    source "<openvm-int64>" "Tests.OpenVmInt64" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planOpenVm compiled
  expect plan.signedNumeric "Int64Cell Plan is signed"
  expect (plan.states.map (·.name) == #["count"])
    "Int64Cell plan must carry the count state field"
  let some inc := plan.entries[0]? |
    throw <| IO.userError "missing increment entry"
  expect (inc.resultKind == .int64) "increment result Int64"
  let signedOverflowOk :=
    match inc.checks[0]? with
    | some ck => inc.checks.size == 1 && ck.kind == .overflow
    | none => false
  expect signedOverflowOk
    "signed increment must carry a single overflow check"
  let some get := plan.views[0]? |
    throw <| IO.userError "missing get view"
  expect (get.resultKind == .int64) "get view Int64"
  liftResult <| Targets.OpenVM.validatePlan plan
  let files ← liftResult <| buildOpenVm compiled
  let some mainRs := files.find? (·.path == "guest/src/main.rs") |
    throw <| IO.userError "openvm: missing guest/src/main.rs"
  let rs := mainRs.contents
  expect (rs.contains "pub count: i64,")
    "signed State struct must carry i64 count"
  expect (rs.contains "pub fn initialize(initial: i64) -> State {")
    "signed initialize must take i64"
  expect (rs.contains "pub fn increment(state: &mut State, delta: i64) -> Result<i64, u32> {")
    "signed increment must use i64 params/result"
  expect (rs.contains "checked_add(delta).ok_or(1u32)?")
    "signed increment must use i64 checked_add with overflow code 1"
  expect (rs.contains "pub fn get(state: &State) -> i64 {")
    "signed get must return i64"
  expect (!rs.contains "pub count: u64,")
    "signed program must not emit u64 state fields"

/-- Homogeneous Array UInt64 2 flatten: two Plan/guest `u64` leaves, no `[u64; N]`. -/
unsafe def testArrayBoxFlatten : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program ArrayBox where\n" ++
    "  state slots : Array UInt64 2\n" ++
    "  init() do\n" ++
    "    slots[0] := 0\n" ++
    "    slots[1] := 0\n" ++
    "  entry set0(v : UInt64) : UInt64 do\n" ++
    "    slots[0] := v\n" ++
    "    return slots[0]\n" ++
    "  view get0() : UInt64 do\n" ++
    "    return slots[0]\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<openvm-array-box>" "Tests.OpenVmArrayBox" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planOpenVm compiled
  expect (!plan.signedNumeric) "ArrayBox stays unsigned"
  expect (plan.states.map (·.name) == #["slots_0", "slots_1"])
    "Array UInt64 2 must flatten to slots_0/slots_1 Plan leaves"
  match plan.initializer with
  | some initFn =>
      expect (initFn.stores.size == 2)
        "ArrayBox init must store both flattened leaves"
  | none => throw <| IO.userError "ArrayBox must have an initializer"
  liftResult <| Targets.OpenVM.validatePlan plan
  let files ← liftResult <| buildOpenVm compiled
  let some mainRs := files.find? (·.path == "guest/src/main.rs") |
    throw <| IO.userError "openvm: missing guest/src/main.rs"
  let rs := mainRs.contents
  expect (rs.contains "pub slots_0: u64,")
    "guest State must carry flattened slots_0 u64 field"
  expect (rs.contains "pub slots_1: u64,")
    "guest State must carry flattened slots_1 u64 field"
  expect (!rs.contains "[u64; 2]")
    "Array flatten must not emit a Rust [u64; N] field"
  expect (!rs.contains "Vec<")
    "Array flatten must not emit a Vec field"

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
    source "<openvm-array-n9>" "Tests.OpenVmArrayNine" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  match planOpenVm compiled with
  | .error (.planInvariant .openvm msg) =>
      expect (msg.contains "cap" || msg.contains "container")
        s!"Array UInt64 9 must cite cap/container, got: {msg}"
  | .error e => throw <| IO.userError s!"expected planInvariant .openvm, got {e.render}"
  | .ok _ => throw <| IO.userError "Array UInt64 9 must fail closed at OpenVM plan"

/-- Non-UInt64 Array element stays fail closed. -/
unsafe def testArrayNonUInt64ElementFc : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program ArrBool where\n" ++
    "  state slots : Array Bool 2\n" ++
    "  init() do\n" ++
    "    slots[0] := false\n" ++
    "    slots[1] := false\n" ++
    "  entry set0(v : UInt64) : UInt64 do\n" ++
    "    slots[0] := false\n" ++
    "    return v\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<openvm-arr-bool>" "Tests.OpenVmArrBool" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  match planOpenVm compiled with
  | .error (.planInvariant .openvm msg) =>
      expect (msg.contains "element" || msg.contains "UInt64" ||
          msg.contains "container")
        s!"Array Bool must cite element/UInt64/container, got: {msg}"
  | .error e => throw <| IO.userError s!"expected planInvariant .openvm, got {e.render}"
  | .ok _ => throw <| IO.userError "Array Bool element must fail closed at OpenVM plan"

unsafe def testArrRetBox : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program ArrRetBox where\n" ++
    "  state slots : Array UInt64 2\n" ++
    "  init() do\n" ++
    "    slots[0] := 0\n" ++
    "    slots[1] := 0\n" ++
    "  entry peek() : Array UInt64 2 do\n" ++
    "    return slots\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<openvm-arr-ret>" "Tests.OpenVmArrRetBox" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planOpenVm compiled
  let some e := plan.entries[0]? |
    throw <| IO.userError "ArrRetBox must emit an entry"
  expect (e.resultKind == .aggregate 2)
    s!"ArrRetBox entry must be aggregate 2, got {repr e.resultKind}"
  liftResult <| Targets.OpenVM.validatePlan plan
  let files ← liftResult <| buildOpenVm compiled
  expect (!files.isEmpty) "ArrRetBox must emit nonempty files"
  let some mainRs := files.find? (·.path == "guest/src/main.rs") |
    throw <| IO.userError "openvm: missing guest/src/main.rs"
  expect (mainRs.contents.contains "Result<(u64, u64), u32>")
    "ArrRetBox entry must return a guest u64 tuple Result"

/-- signedNumeric Int64 programs cannot carry Array state. -/
unsafe def testSignedNumericArrayFc : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program MixArrInt64 where\n" ++
    "  state slots : Array UInt64 2\n" ++
    "  init() do\n" ++
    "    slots[0] := 0\n" ++
    "    slots[1] := 0\n" ++
    "  entry set0(v : Int64) : Int64 do\n" ++
    "    return v\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<openvm-mix-arr-int64>" "Tests.OpenVmMixArrInt64" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  match planOpenVm compiled with
  | .error (.planInvariant .openvm msg) =>
      expect (msg.contains "Array" && msg.contains "UInt64")
        s!"mixed Int64+Array UInt64 must cite Array/UInt64, got: {msg}"
  | .error e => throw <| IO.userError s!"expected planInvariant .openvm, got {e.render}"
  | .ok _ => throw <| IO.userError "signedNumeric+Array must fail closed at OpenVM plan"

/-- Homogeneous Option UInt64 state: two Plan/guest `u64` leaves, no Rust Option. -/
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
    source "<openvm-opt-box>" "Tests.OpenVmOptBox" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planOpenVm compiled
  expect (!plan.signedNumeric) "OptBox stays unsigned"
  expect (plan.states.map (·.name) == #["o_tag", "o_p0"])
    "Option UInt64 must flatten to o_tag/o_p0 Plan leaves"
  match plan.initializer with
  | some initFn =>
      expect (initFn.stores.size == 2)
        "OptBox init must store both Option leaves"
  | none => throw <| IO.userError "OptBox must have an initializer"
  liftResult <| Targets.OpenVM.validatePlan plan
  let files ← liftResult <| buildOpenVm compiled
  let some mainRs := files.find? (·.path == "guest/src/main.rs") |
    throw <| IO.userError "openvm: missing guest/src/main.rs"
  let rs := mainRs.contents
  expect (rs.contains "pub o_tag: u64,")
    "guest State must carry flattened o_tag u64 field"
  expect (rs.contains "pub o_p0: u64,")
    "guest State must carry flattened o_p0 u64 field"
  expect (!rs.contains "Option<")
    "Option flatten must not emit a Rust Option<u64> field"
  expect (!rs.contains "enum ")
    "Option flatten must not emit a Rust enum"

/-- Non-UInt64 Option payload stays fail closed. -/
unsafe def testOptionInt64ElementFc : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program OptI64 where\n" ++
    "  state o : Option Int64\n" ++
    "  init() do\n" ++
    "    o := Option.none()\n" ++
    "  entry set(v : UInt64) : UInt64 do\n" ++
    "    return v\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<openvm-opt-i64>" "Tests.OpenVmOptI64" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  match planOpenVm compiled with
  | .error (.planInvariant .openvm msg) =>
      expect (msg.contains "UInt64 payload" || msg.contains "Option")
        s!"Option Int64 must cite UInt64 payload/Option, got: {msg}"
  | .error e => throw <| IO.userError s!"expected planInvariant .openvm, got {e.render}"
  | .ok _ => throw <| IO.userError "Option Int64 payload must fail closed at OpenVM plan"

unsafe def testOptRetBox : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program OptRetBox where\n" ++
    "  state o : Option UInt64\n" ++
    "  init() do\n" ++
    "    o := Option.none()\n" ++
    "  entry peek() : Option UInt64 do\n" ++
    "    return o\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<openvm-opt-ret>" "Tests.OpenVmOptRetBox" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planOpenVm compiled
  let some e := plan.entries[0]? |
    throw <| IO.userError "OptRetBox must emit an entry"
  expect (e.resultKind == .aggregate 2)
    s!"OptRetBox entry must be aggregate 2, got {repr e.resultKind}"
  liftResult <| Targets.OpenVM.validatePlan plan
  let files ← liftResult <| buildOpenVm compiled
  expect (!files.isEmpty) "OptRetBox must emit nonempty files"

unsafe def testMaybeRetBox : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program MaybeRetBox where\n" ++
    "  enum Maybe where\n" ++
    "    | None\n" ++
    "    | Some(UInt64)\n" ++
    "  state m : Maybe\n" ++
    "  init() do\n" ++
    "    m := Maybe.None()\n" ++
    "  entry peek() : Maybe do\n" ++
    "    return m\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<openvm-maybe-ret>" "Tests.OpenVmMaybeRetBox" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planOpenVm compiled
  let some e := plan.entries[0]? |
    throw <| IO.userError "MaybeRetBox must emit an entry"
  expect (e.resultKind == .aggregate 2)
    s!"MaybeRetBox entry must be aggregate 2, got {repr e.resultKind}"
  liftResult <| Targets.OpenVM.validatePlan plan
  let files ← liftResult <| buildOpenVm compiled
  expect (!files.isEmpty) "MaybeRetBox must emit nonempty files"

unsafe def testPairRetEntry : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program PairRetEntry where\n" ++
    "  struct Pair where\n" ++
    "    a : UInt64\n" ++
    "    b : UInt64\n" ++
    "  entry makePair(x : UInt64, y : UInt64) : Pair do\n" ++
    "    return Pair.new(x, y)\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<openvm-pair-ret-entry>" "Tests.OpenVmPairRetEntry" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planOpenVm compiled
  let some e := plan.entries[0]? |
    throw <| IO.userError "PairRetEntry must emit an entry"
  expect (e.resultKind == .aggregate 2)
    s!"PairRetEntry entry must be aggregate 2, got {repr e.resultKind}"
  liftResult <| Targets.OpenVM.validatePlan plan
  let files ← liftResult <| buildOpenVm compiled
  expect (!files.isEmpty) "PairRetEntry must emit nonempty files"

/-- signedNumeric Int64 programs cannot carry Option state. -/
unsafe def testSignedNumericOptionFc : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program MixOptInt64 where\n" ++
    "  state o : Option UInt64\n" ++
    "  init() do\n" ++
    "    o := Option.none()\n" ++
    "  entry set0(v : Int64) : Int64 do\n" ++
    "    return v\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<openvm-mix-opt-int64>" "Tests.OpenVmMixOptInt64" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  match planOpenVm compiled with
  | .error (.planInvariant .openvm msg) =>
      expect (msg.contains "Option" && msg.contains "UInt64")
        s!"mixed Int64+Option UInt64 must cite Option/UInt64, got: {msg}"
  | .error e => throw <| IO.userError s!"expected planInvariant .openvm, got {e.render}"
  | .ok _ => throw <| IO.userError "signedNumeric+Option must fail closed at OpenVM plan"

/-- Map UInt64 UInt64 dense cap-8: 24 Plan leaves, empty + IndexSet. -/
unsafe def testMapMiniFlatten : IO Unit := do
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
    source "<openvm-map-mini>" "Tests.OpenVmMapMini" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planOpenVm compiled
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
  liftResult <| Targets.OpenVM.validatePlan plan
  let files ← liftResult <| buildOpenVm compiled
  let some mainRs := files.find? (·.path == "guest/src/main.rs") |
    throw <| IO.userError "openvm: missing guest/src/main.rs"
  let rs := mainRs.contents
  expect (rs.contains "pub m_0: u64,")
    "guest State must carry flattened m_0 u64 field"
  expect (rs.contains "pub m_23: u64,")
    "guest State must carry flattened m_23 u64 field"
  expect (!rs.contains "HashMap")
    "Map flatten must not emit HashMap"
  expect (!rs.contains "std::collections")
    "Map flatten must not emit std::collections"
  expect (!rs.contains "Vec<")
    "Map flatten must not emit a Vec field"
  expect (!rs.contains "[u64;")
    "Map flatten must not emit a Rust [u64; N] field"

/-- Map of Int64 stays fail closed. -/
unsafe def testMapInt64ElementFc : IO Unit := do
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
    source "<openvm-map-int>" "Tests.OpenVmMapInt" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  match planOpenVm compiled with
  | .error (.planInvariant .openvm msg) =>
      expect (msg.contains "Map state admits only Map UInt64 UInt64")
        s!"Map Int64 must cite Map UInt64 UInt64, got: {msg}"
  | .error e => throw <| IO.userError s!"expected planInvariant .openvm, got {e.render}"
  | .ok _ => throw <| IO.userError "Map Int64 must fail closed at OpenVM plan"

/-- B-RET-MAP: Map return is 24 leaves, not an 8-leaf cap raise. -/
unsafe def testMapReturnFc : IO Unit := do
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
    source "<openvm-map-ret>" "Tests.OpenVmMapRet" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planOpenVm compiled
  let some ent := plan.entries[0]? |
    throw <| IO.userError "MapRet must emit an entry"
  expect (ent.resultKind == .aggregate 24)
    s!"MapRet entry must be aggregate 24, got {repr ent.resultKind}"
  expect (ent.leaves.size == 24) "MapRet must carry 24 Map leaves"
  liftResult <| Targets.OpenVM.validatePlan plan
  let files ← liftResult <| buildOpenVm compiled
  let some mainRs := files.find? (·.path == "guest/src/main.rs") |
    throw <| IO.userError "openvm: missing guest/src/main.rs"
  expect (mainRs.contents.contains "Result<(u64, u64, u64, u64, u64, u64, u64, u64, u64, u64, u64, u64, u64, u64, u64, u64, u64, u64, u64, u64, u64, u64, u64, u64), u32>")
    "MapRet entry must return a guest 24-u64 tuple Result"

/-- signedNumeric Int64 programs cannot carry Map state. -/
unsafe def testSignedNumericMapFc : IO Unit := do
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
    source "<openvm-signed-map>" "Tests.OpenVmMixMap" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  match planOpenVm compiled with
  | .error (.planInvariant .openvm msg) =>
      expect (msg.contains "Map" && msg.contains "UInt64")
        s!"mixed Int64+Map UInt64 must cite Map/UInt64, got: {msg}"
  | .error e => throw <| IO.userError s!"expected planInvariant .openvm, got {e.render}"
  | .ok _ => throw <| IO.userError "signedNumeric+Map must fail closed at OpenVM plan"

/-- Mixing Int64 state with a UInt64 view/result is fail closed. -/
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
    source "<openvm-mix-int64>" "Tests.OpenVmMixInt64" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  match planOpenVm compiled with
  | .error (.planInvariant .openvm msg) =>
      expect (msg.contains "mixes")
        s!"mixed Int64/UInt64 must name mixes, got: {msg}"
  | .error e => throw <| IO.userError s!"expected planInvariant .openvm, got {e.render}"
  | .ok _ => throw <| IO.userError "mixed Int64/UInt64 must fail closed at OpenVM plan"

/-- Fail closed: Int32 (narrow signed; Int64 is the admitted width). -/
unsafe def testFailClosedInt32 : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program I32 where\n" ++
    "  entry id(x : Int32) : Int32 do\n" ++
    "    return x\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<openvm-int32>" "Tests.OpenVmInt32" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  match planOpenVm compiled with
  | .error (.planInvariant .openvm msg) =>
      expect (msg.contains "UInt64/Int64" || msg.contains "width")
        s!"Int32 must fail closed on the width needle, got: {msg}"
  | .error e => throw <| IO.userError s!"expected planInvariant .openvm, got {e.render}"
  | .ok _ => throw <| IO.userError "Int32 must fail closed at OpenVM plan"

/-- OPENVM-1a: grammar-valid but unregistered profile stays unknown.
    Do not invent a third OpenVM CodegenProfileId. -/
unsafe def testUnknownProfileFailClosed : IO Unit := do
  match CodegenProfileId.parse? "not-a-real-profile-v1" with
  | none =>
      throw <| IO.userError "not-a-real-profile-v1 must remain grammar-valid"
  | some unknown =>
      match Targets.BuildSelectionV1.resolveBuildSelectionV1
          TargetId.openvm (some unknown) with
      | .error e =>
          expect (e.code == "PF-PROFILE-UNKNOWN")
            s!"unknown OpenVM profile must be PF-PROFILE-UNKNOWN, got {e.code}: {e.render}"
      | .ok sel =>
          throw <| IO.userError
            s!"unknown OpenVM profile must fail closed, got {sel.codegenProfile}"

unsafe def testArrInt64Flatten : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program ArrInt64 where\n" ++
    "  state slots : Array Int64 2\n" ++
    "  init() do\n" ++
    "    slots[0] := 0\n" ++
    "    slots[1] := 0\n" ++
    "  entry set0(v : Int64) : Int64 do\n" ++
    "    slots[0] := v\n" ++
    "    return slots[0]\n" ++
    "  view get0() : Int64 do\n" ++
    "    return slots[0]\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<openvm-arr-int64>" "Tests.OpenVmArrInt64" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planOpenVm compiled
  expect plan.signedNumeric "ArrInt64 Plan is signed"
  expect (plan.states.map (·.name) == #["slots_0", "slots_1"])
    "Array Int64 2 flattens to slots_0/slots_1"
  liftResult <| Targets.OpenVM.validatePlan plan
  let files ← liftResult <| buildOpenVm compiled
  let some mainRs := files.find? (·.path == "guest/src/main.rs") |
    throw <| IO.userError "openvm: missing guest/src/main.rs"
  expect (mainRs.contents.contains "pub slots_0: i64,") "guest slots_0 i64"
  expect (mainRs.contents.contains "pub slots_1: i64,") "guest slots_1 i64"
  expect (!mainRs.contents.contains "Vec<") "no Vec"

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
    source "<openvm-opt-int64>" "Tests.OpenVmOptInt64" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planOpenVm compiled
  expect plan.signedNumeric "OptInt64 Plan is signed"
  expect (plan.states.map (·.name) == #["o_tag", "o_p0"])
    "Option Int64 flattens to o_tag/o_p0"
  liftResult <| Targets.OpenVM.validatePlan plan
  let files ← liftResult <| buildOpenVm compiled
  let some mainRs := files.find? (·.path == "guest/src/main.rs") |
    throw <| IO.userError "openvm: missing guest/src/main.rs"
  expect (mainRs.contents.contains "pub o_tag: i64,") "guest o_tag i64"
  expect (mainRs.contents.contains "pub o_p0: i64,") "guest o_p0 i64"
  expect (!mainRs.contents.contains "Option<") "no Rust Option"

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
    source "<openvm-map-int64>" "Tests.OpenVmMapInt64" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planOpenVm compiled
  expect plan.signedNumeric "MapInt64 Plan is signed"
  expect (plan.states.size == 24) "Map Int64 flattens to 24 leaves"
  liftResult <| Targets.OpenVM.validatePlan plan
  let files ← liftResult <| buildOpenVm compiled
  let some mainRs := files.find? (·.path == "guest/src/main.rs") |
    throw <| IO.userError "openvm: missing guest/src/main.rs"
  expect (mainRs.contents.contains "pub m_0: i64,") "guest m_0 i64"
  expect (!mainRs.contents.contains "HashMap") "no HashMap"

unsafe def testArrayInt64Return : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program ArrInt64Ret where\n" ++
    "  state slots : Array Int64 2\n" ++
    "  init(a : Int64, b : Int64) do\n" ++
    "    slots[0] := a\n" ++
    "    slots[1] := b\n" ++
    "  entry peek() : Array Int64 2 do\n" ++
    "    return slots\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<openvm-arr-int64-ret>" "Tests.OpenVmArrInt64Ret" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planOpenVm compiled
  expect plan.signedNumeric "ArrInt64Ret Plan is signed"
  let some e := plan.entries[0]? |
    throw <| IO.userError "ArrInt64Ret must emit an entry"
  expect (e.resultKind == .aggregate 2)
    s!"ArrInt64Ret entry must be aggregate 2, got {repr e.resultKind}"
  expect (e.leafIsInt == #[true, true]) "ArrInt64Ret leaves must be signed"
  liftResult <| Targets.OpenVM.validatePlan plan
  let files ← liftResult <| buildOpenVm compiled
  let some mainRs := files.find? (·.path == "guest/src/main.rs") |
    throw <| IO.userError "openvm: missing guest/src/main.rs"
  expect (mainRs.contents.contains "(i64, i64)" || mainRs.contents.contains "i64, i64")
    "ArrInt64Ret guest must emit an i64 tuple"

unsafe def testOptionInt64Return : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program OptInt64Ret where\n" ++
    "  state slot : Option Int64\n" ++
    "  init(v : Int64) do\n" ++
    "    slot := Option.some(v)\n" ++
    "  entry peek() : Option Int64 do\n" ++
    "    return slot\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<openvm-opt-int64-ret>" "Tests.OpenVmOptInt64Ret" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planOpenVm compiled
  expect plan.signedNumeric "OptInt64Ret Plan is signed"
  let some e := plan.entries[0]? |
    throw <| IO.userError "OptInt64Ret must emit an entry"
  expect (e.resultKind == .aggregate 2)
    s!"OptInt64Ret entry must be aggregate 2, got {repr e.resultKind}"
  expect (e.leafIsInt == #[false, true])
    s!"OptInt64Ret leaves must be tag unsigned + payload isInt, got {e.leafIsInt}"
  liftResult <| Targets.OpenVM.validatePlan plan

unsafe def testMapInt64Return : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program MapInt64Ret where\n" ++
    "  state m : Map Int64 Int64\n" ++
    "  init(v : Int64) do\n" ++
    "    m := Map.empty()\n" ++
    "  entry peek() : Map Int64 Int64 do\n" ++
    "    return m\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<openvm-map-int64-ret>" "Tests.OpenVmMapInt64Ret" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planOpenVm compiled
  expect plan.signedNumeric "MapInt64Ret Plan is signed"
  let some e := plan.entries[0]? |
    throw <| IO.userError "MapInt64Ret must emit an entry"
  expect (e.resultKind == .aggregate 24)
    s!"MapInt64Ret entry must be aggregate 24, got {repr e.resultKind}"
  expect (e.leaves.size == 24) "MapInt64Ret must carry 24 Map leaves"
  expect ((List.range 24).all (fun i =>
      e.leafIsInt[i]! == (i % 3 == 2)))
    s!"MapInt64Ret val slots must be isInt, got {e.leafIsInt}"
  liftResult <| Targets.OpenVM.validatePlan plan

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
    source "<openvm-arr-int64-n9>" "Tests.OpenVmArrInt64Nine" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  match planOpenVm compiled with
  | .error (.planInvariant .openvm msg) =>
      expect (msg.contains "cap" || msg.contains "1..8")
        s!"Array Int64 9, got: {msg}"
  | .error e => throw <| IO.userError s!"expected planInvariant .openvm, got {e.render}"
  | .ok _ => throw <| IO.userError "Array Int64 9 must fail closed"

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
    source "<openvm-point-box>" "Tests.OpenVmPointBox" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planOpenVm compiled
  expect (plan.states.map (·.name) == #["p_x", "p_y"])
    "PointBox must flatten to p_x/p_y"
  liftResult <| Targets.OpenVM.validatePlan plan
  let files ← liftResult <| buildOpenVm compiled
  expect (!files.isEmpty) "PointBox must materialize files"
  let some mainRs := files.find? (·.path == "guest/src/main.rs") |
    throw <| IO.userError "openvm: missing guest/src/main.rs"
  expect (mainRs.contents.contains "pub p_x: u64,")
    "guest State must carry flattened p_x"
  expect (mainRs.contents.contains "pub p_y: u64,")
    "guest State must carry flattened p_y"

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
    source "<openvm-maybe-mark>" "Tests.OpenVmMaybeMark" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planOpenVm compiled
  expect (plan.states.map (·.name) == #["m_tag", "m_p0"])
    "MaybeMark must flatten to m_tag/m_p0"
  liftResult <| Targets.OpenVM.validatePlan plan
  let files ← liftResult <| buildOpenVm compiled
  expect (!files.isEmpty) "MaybeMark must materialize files"
  let some mainRs := files.find? (·.path == "guest/src/main.rs") |
    throw <| IO.userError "openvm: missing guest/src/main.rs"
  expect (mainRs.contents.contains "pub m_tag: u64,")
    "guest State must carry flattened m_tag"
  expect (mainRs.contents.contains "pub m_p0: u64,")
    "guest State must carry flattened m_p0"

unsafe def testArrViewRet : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program ArrViewRet where\n" ++
    "  state slots : Array UInt64 2\n" ++
    "  init() do\n" ++
    "    slots[0] := 0\n" ++
    "    slots[1] := 0\n" ++
    "  view peek() : Array UInt64 2 do\n" ++
    "    return slots\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<openvm-arr-view-ret>" "Tests.OpenVmArrViewRet" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planOpenVm compiled
  let some v := plan.views[0]? |
    throw <| IO.userError "ArrViewRet must emit a view"
  expect (v.resultKind == .aggregate 2)
    s!"ArrViewRet view must be aggregate 2, got {repr v.resultKind}"
  liftResult <| Targets.OpenVM.validatePlan plan
  let files ← liftResult <| buildOpenVm compiled
  expect (!files.isEmpty) "ArrViewRet must emit nonempty files"
  let some mainRs := files.find? (·.path == "guest/src/main.rs") |
    throw <| IO.userError "openvm: missing guest/src/main.rs"
  expect (mainRs.contents.contains "-> (u64, u64)")
    "ArrViewRet view must return a guest u64 tuple"

unsafe def testBytesViewRet : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program BytesRetBox where\n" ++
    "  state b : Bytes 4\n" ++
    "  init() do\n" ++
    "    b[0] := 0\n" ++
    "  view get() : Bytes 4 do\n" ++
    "    return b\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<openvm-bytes-view-ret>" "Tests.OpenVmBytesRetBox" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planOpenVm compiled
  let some v := plan.views[0]? |
    throw <| IO.userError "BytesRetBox must emit a view"
  expect (v.resultKind == .aggregate 4)
    s!"BytesRetBox view must be aggregate 4, got {repr v.resultKind}"
  liftResult <| Targets.OpenVM.validatePlan plan
  let files ← liftResult <| buildOpenVm compiled
  let some mainRs := files.find? (·.path == "guest/src/main.rs") |
    throw <| IO.userError "openvm: missing guest/src/main.rs"
  expect (mainRs.contents.contains "-> (u64, u64, u64, u64)")
    "BytesRetBox view must return a guest 4-u64 tuple"
  let entrySrc :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program BytesRetEntry where\n" ++
    "  state b : Bytes 4\n" ++
    "  init() do\n" ++
    "    b[0] := 0\n" ++
    "  entry peek() : Bytes 4 do\n" ++
    "    return b\n"
  let entryParsed ← liftResult (← session.selectProgramV1
    entrySrc "<openvm-bytes-entry-ret>" "Tests.OpenVmBytesRetEntry" none)
  let entryCompiled ← liftResult <| Compiler.compileValidatedSourceV1 entryParsed
  let entryPlan ← liftResult <| planOpenVm entryCompiled
  let some ent := entryPlan.entries[0]? |
    throw <| IO.userError "BytesRetEntry must emit an entry"
  expect (ent.resultKind == .aggregate 4)
    s!"BytesRetEntry entry must be aggregate 4, got {repr ent.resultKind}"
  liftResult <| Targets.OpenVM.validatePlan entryPlan
  let entryFiles ← liftResult <| buildOpenVm entryCompiled
  let some entryMain := entryFiles.find? (·.path == "guest/src/main.rs") |
    throw <| IO.userError "openvm: missing guest/src/main.rs"
  expect (entryMain.contents.contains "Result<(u64, u64, u64, u64), u32>")
    "BytesRetEntry entry must return a guest 4-u64 tuple Result"

unsafe def testBytesParam : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program BytesParam where\n" ++
    "  state pad : UInt64\n" ++
    "  init() do\n" ++
    "    pad := 0\n" ++
    "  entry put(b : Bytes 2) : UInt64 do\n" ++
    "    return pad\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<openvm-bytes-param>" "Tests.OpenVmBytesParam" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planOpenVm compiled
  let some ent := plan.entries[0]? |
    throw <| IO.userError "BytesParam must emit an entry"
  expect (ent.params == #["b_0", "b_1"])
    s!"BytesParam must flatten to b_0/b_1, got {ent.params}"
  liftResult <| Targets.OpenVM.validatePlan plan
  let files ← liftResult <| buildOpenVm compiled
  expect (!files.isEmpty) "BytesParam must emit nonempty files"

unsafe def testOptionParam : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program OptParam where\n" ++
    "  state pad : UInt64\n" ++
    "  init() do\n" ++
    "    pad := 0\n" ++
    "  entry put(o : Option UInt64) : UInt64 do\n" ++
    "    return pad\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<openvm-opt-param>" "Tests.OpenVmOptParam" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planOpenVm compiled
  let some ent := plan.entries[0]? |
    throw <| IO.userError "OptParam must emit an entry"
  expect (ent.params == #["o_tag", "o_p0"])
    s!"OptParam must flatten to o_tag/o_p0, got {ent.params}"
  liftResult <| Targets.OpenVM.validatePlan plan

unsafe def testArrayParam : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program ArrParam where\n" ++
    "  state pad : UInt64\n" ++
    "  init() do\n" ++
    "    pad := 0\n" ++
    "  entry put(a : Array UInt64 2) : UInt64 do\n" ++
    "    return pad\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<openvm-arr-param>" "Tests.OpenVmArrParam" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planOpenVm compiled
  let some ent := plan.entries[0]? |
    throw <| IO.userError "ArrParam must emit an entry"
  expect (ent.params == #["a_0", "a_1"])
    s!"ArrParam must flatten to a_0/a_1, got {ent.params}"
  liftResult <| Targets.OpenVM.validatePlan plan

unsafe def testMapParam : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program MapParam where\n" ++
    "  state pad : UInt64\n" ++
    "  init() do\n" ++
    "    pad := 0\n" ++
    "  entry put(m : Map UInt64 UInt64) : UInt64 do\n" ++
    "    return pad\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<openvm-map-param>" "Tests.OpenVmMapParam" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planOpenVm compiled
  let some ent := plan.entries[0]? |
    throw <| IO.userError "MapParam must emit an entry"
  let expected := (List.range 24).toArray.map (fun i => s!"m_{i}")
  expect (ent.params == expected)
    s!"MapParam must flatten to 24 occ/key/val leaves, got {ent.params}"
  liftResult <| Targets.OpenVM.validatePlan plan

unsafe def testOptViewRet : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program OptViewRet where\n" ++
    "  state o : Option UInt64\n" ++
    "  init() do\n" ++
    "    o := Option.none()\n" ++
    "  view peek() : Option UInt64 do\n" ++
    "    return o\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<openvm-opt-view-ret>" "Tests.OpenVmOptViewRet" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planOpenVm compiled
  let some v := plan.views[0]? |
    throw <| IO.userError "OptViewRet must emit a view"
  expect (v.resultKind == .aggregate 2)
    s!"OptViewRet view must be aggregate 2, got {repr v.resultKind}"
  liftResult <| Targets.OpenVM.validatePlan plan
  let files ← liftResult <| buildOpenVm compiled
  expect (!files.isEmpty) "OptViewRet must emit nonempty files"

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
    "  view getPoint() : Point do\n" ++
    "    return p\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<openvm-point-view-ret>" "Tests.OpenVmPointViewRet" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planOpenVm compiled
  let some v := plan.views[0]? |
    throw <| IO.userError "PointViewRet must emit a view"
  expect (v.resultKind == .aggregate 2)
    s!"PointViewRet view must be aggregate 2, got {repr v.resultKind}"
  liftResult <| Targets.OpenVM.validatePlan plan
  let files ← liftResult <| buildOpenVm compiled
  expect (!files.isEmpty) "PointViewRet must emit nonempty files"

unsafe def testMaybeViewRet : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program MaybeViewRet where\n" ++
    "  enum Maybe where\n" ++
    "    | None\n" ++
    "    | Some(UInt64)\n" ++
    "  state m : Maybe\n" ++
    "  init() do\n" ++
    "    m := Maybe.None()\n" ++
    "  view peek() : Maybe do\n" ++
    "    return m\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<openvm-maybe-view-ret>" "Tests.OpenVmMaybeViewRet" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planOpenVm compiled
  let some v := plan.views[0]? |
    throw <| IO.userError "MaybeViewRet must emit a view"
  expect (v.resultKind == .aggregate 2)
    s!"MaybeViewRet view must be aggregate 2, got {repr v.resultKind}"
  liftResult <| Targets.OpenVM.validatePlan plan
  let files ← liftResult <| buildOpenVm compiled
  expect (!files.isEmpty) "MaybeViewRet must emit nonempty files"

unsafe def run : IO Unit := do
  testStateCellOpenVmSource
  testMaterializeDeterminism
  testCapabilityProductPath
  testElfProfileSelection
  testElfProfileFinalize
  testUnknownProfileFailClosed
  testFailClosedCall
  testCryptoSha256StayFailClosed
  testContextReadStayFailClosed
  testEnvReadNativeStayFailClosed
  testFailClosedEmit
  testFailClosedInvariant
  testFailClosedPfAssets
  testPrincipalIdentityLeaves
  testMulDivModAdmit
  testSignedMulAdmit
  testFailClosedBitNot
  testLoopSum
  testIfFlow
  testBranchFlow
  testMaybeMatch
  testFailClosedConstant
  testFailClosedPrivateState
  testInt64Cell
  testArrayBoxFlatten
  testArrInt64Flatten
  testArrayN9FailClosed
  testArrayInt64N9FailClosed
  testArrayNonUInt64ElementFc
  testArrRetBox
  testArrayInt64Return
  testOptionInt64Return
  testMapInt64Return
  testSignedNumericArrayFc
  testOptBoxAdmit
  testOptInt64Flatten
  testOptionInt64ElementFc
  testOptRetBox
  testMaybeRetBox
  testPairRetEntry
  testSignedNumericOptionFc
  testMapMiniFlatten
  testMapInt64Flatten
  testMapInt64ElementFc
  testMapReturnFc
  testSignedNumericMapFc
  testPointBoxFlatten
  testMaybeMarkFlatten
  testArrViewRet
  testBytesViewRet
  testBytesParam
  testOptionParam
  testArrayParam
  testMapParam
  testOptViewRet
  testPointViewRet
  testMaybeViewRet
  testMixedInt64UInt64Fc
  testFailClosedInt32
  IO.println "Tests.Materialization.OpenVmGuestSourceV1: ok"

end Tests.Materialization.OpenVmGuestSourceV1
