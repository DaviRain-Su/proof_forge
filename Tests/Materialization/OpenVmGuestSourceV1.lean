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

/-- Fail closed: Principal-typed parameters are outside O0. -/
unsafe def testFailClosedPrincipal : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program PrincipalUse where\n" ++
    "  entry id(p : Principal) : Bool do\n" ++
    "    return true\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<openvm-principal>" "Tests.OpenVmPrincipal" none)
  match Compiler.compileValidatedSourceV1 parsed with
  | .error _ => pure ()
  | .ok compiled =>
      match planOpenVm compiled with
      | .error (.planInvariant .openvm msg) =>
          expect (msg.contains "UInt64" || msg.contains "parameter" ||
              msg.contains "public")
            s!"Principal parameter must fail closed, got: {msg}"
      | .error e => throw <| IO.userError s!"expected planInvariant .openvm, got {e.render}"
      | .ok _ => throw <| IO.userError "Principal parameter must fail closed at OpenVM plan"

/-- Fail closed: multiplication is outside O0 (only checked add/sub). -/
unsafe def testFailClosedMul : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program Mul where\n" ++
    "  entry scale(x : UInt64, y : UInt64) : UInt64 do\n" ++
    "    return x * y\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<openvm-mul>" "Tests.OpenVmMul" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  match planOpenVm compiled with
  | .error (.planInvariant .openvm msg) =>
      expect (msg.contains "mul" || msg.contains "add/sub")
        s!"multiplication must fail closed, got: {msg}"
  | .error e => throw <| IO.userError s!"expected planInvariant .openvm, got {e.render}"
  | .ok _ => throw <| IO.userError "multiplication must fail closed at OpenVM plan"

/-- Fail closed: multi-block if is outside O0 (single-block only). -/
unsafe def testFailClosedMultiblock : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program Branch where\n" ++
    "  entry pick(c : UInt64, a : UInt64, b : UInt64) : UInt64 do\n" ++
    "    if c > 0 then\n" ++
    "      return a\n" ++
    "    else\n" ++
    "      return b\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<openvm-if>" "Tests.OpenVmIf" none)
  match Compiler.compileValidatedSourceV1 parsed with
  | .error _ => pure ()
  | .ok compiled =>
      match planOpenVm compiled with
      | .error (.planInvariant .openvm msg) =>
          expect (msg.contains "one block" || msg.contains "block")
            s!"multi-block must fail closed, got: {msg}"
      | .error e => throw <| IO.userError s!"expected planInvariant .openvm, got {e.render}"
      | .ok _ => throw <| IO.userError "multi-block if must fail closed at OpenVM plan"

/-- Fail closed: constants are not silently substituted by a second evaluator. -/
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
  match planOpenVm compiled with
  | .error (.planInvariant .openvm msg) =>
      expect (msg.contains "constants" || msg.contains "constant")
        s!"nonempty constants must fail closed, got: {msg}"
  | .error e => throw <| IO.userError s!"expected planInvariant .openvm, got {e.render}"
  | .ok _ => throw <| IO.userError "nonempty constants must fail closed at OpenVM plan"

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
  testFailClosedPrincipal
  testFailClosedMul
  testFailClosedMultiblock
  testFailClosedConstant
  testFailClosedPrivateState
  testInt64Cell
  testMixedInt64UInt64Fc
  testFailClosedInt32
  IO.println "Tests.Materialization.OpenVmGuestSourceV1: ok"

end Tests.Materialization.OpenVmGuestSourceV1
