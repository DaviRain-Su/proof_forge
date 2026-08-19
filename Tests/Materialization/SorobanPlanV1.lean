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

/-- CAP-4 / CAP-D-SOR-LEDGER: S0 source-only Plan admits exact
    `pf.crypto.sha256` UInt256→UInt256 as `env.crypto().sha256` over the
    Semantic canonical 32-byte LE valueBytes (4×u64 LE limbs). UInt256 is
    plumbing-only (locals as sha256 in/out); state/param/result stay FC.
    `pf.crypto.keccak256` and sibling QNs keep the named host-binding FC.
    Finalize stays zero-tool / non-deployable. -/
unsafe def testCryptoSha256Admitted : IO Unit := do
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
          s!"{label} must Plan fail closed"
  let cryptoBodyU256 (qn : String) : String :=
    "  state pad : UInt64\n" ++
      "  init() do\n" ++
      "    pad := 0\n" ++
      "  entry probe() : UInt64 do\n" ++
      "    let w : UInt256 := 0\n" ++
      "    let h : UInt256 := call " ++ qn ++ "(w)\n" ++
      "    return pad\n" ++
      "  view get() : UInt64 do\n" ++
      "    return pad\n"
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program Sha256Soroban where\n" ++
    cryptoBodyU256 "pf.crypto.sha256"
  let parsed ← liftResult (← session.selectProgramV1
    source "<soroban-sha256>" "Tests.SorobanSha256" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planSoroban compiled
  let some probe := plan.entries.find? (·.name == "probe") |
    throw <| IO.userError "Sha256Soroban: missing probe entry"
  expect (probe.sha256Sites.size == 1)
    "Sha256Soroban: plan must record exactly one sha256 site"
  liftResult <| Targets.Soroban.validatePlan plan
  let files ← liftResult <| buildSoroban compiled
  let some rsFile := files.find? (fun f => f.path == "Sha256Soroban.rs") |
    throw <| IO.userError "soroban: missing Sha256Soroban.rs"
  let rs := rsFile.contents
  expect (rs.contains "env.crypto().sha256")
    "Soroban source must call env.crypto().sha256"
  expect (rs.contains "soroban_sdk::Bytes")
    "Soroban source must build soroban_sdk::Bytes from UInt256 LE limbs"
  expect (rs.contains "to_le_bytes")
    "Soroban source must pack Semantic UInt256 LE valueBytes"
  expect (rs.contains "ProofForge Soroban S0")
    "sha256 source must stay an S0 recipe"
  let selection ← liftResult <|
    Targets.BuildSelectionV1.resolveBuildSelectionV1 TargetId.soroban none
  let capability ← liftResult <|
    Targets.resolveEngineeringRequirementsV1 selection compiled
  let artifacts ← liftResult <| Targets.materializeResult capability
  let finalized ← Targets.finalizeMaterializedArtifactsV1
    capability artifacts (System.FilePath.mk ".")
  expect (!FinalizedArtifactsV1.deployableOf finalized)
    "sha256 must not make Soroban S0 deployable"
  expect (FinalizedArtifactsV1.extraFilesOf finalized).isEmpty
    "sha256 must not grow S0 Finalize beyond zero-tool"
  expectPlanFc "Keccak256Soroban" (cryptoBodyU256 "pf.crypto.keccak256")
    "has no Soroban host binding" "keccak256"
  expectPlanFc "Sha256SorobanHashNoPad" (cryptoBodyU256 "pf.crypto.hashNoPad")
    "has no Soroban host binding"
  expectPlanFc "EcdsaRecoverSoroban"
    (cryptoBodyU256 "pf.crypto.ecdsaRecoverSecp256k1")
    "has no Soroban host binding" "ecdsaRecoverSecp256k1"
  expectPlanFc "Sha256SorobanU64"
    ("  state pad : UInt64\n" ++
      "  init() do\n" ++
      "    pad := 0\n" ++
      "  entry probe() : UInt64 do\n" ++
      "    let w : UInt64 := 0\n" ++
      "    let h : UInt64 := call pf.crypto.sha256(w)\n" ++
      "    return pad\n" ++
      "  view get() : UInt64 do\n" ++
      "    return pad\n")
    "pf.crypto.sha256 requires exactly one UInt256 argument and UInt256 result"
  expectPlanFc "Sha256SorobanState"
    ("  state last : UInt256\n" ++
      "  init() do\n" ++
      "    last := 0\n" ++
      "  entry probe() : UInt64 do\n" ++
      "    return 0\n" ++
      "  view get() : UInt64 do\n" ++
      "    return 0\n")
    "UInt256 is admitted only as pf.crypto.sha256 operand/result plumbing"

/-- CAP-X-BYTES-SOR: exact `pf.crypto.sha256Bytes(Bytes N) -> UInt256` on
    init/entry as an independent Plan site (`sha256BytesSites` /
    `sha256BytesLimb`). N is 1..8 because S0 Bytes flatten to N UInt64
    low-8 leaves and the emitter builds `Bytes::from_array(&[u8; N])`.
    Existing CAP-4 UInt256 `sha256Sites` stay a separate record. View,
    sibling QNs, and non-exact ABI fail closed by name. -/
unsafe def testCryptoSha256BytesAdmitted : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let expectPlanFc (label body needle : String)
      (also : String := "") : IO Unit := do
    let source :=
      "import ProofForgeV2\n" ++
      "open ProofForgeV2.Language\n" ++
      s!"program {label} where\n" ++ body
    let parsed ← liftResult (← session.selectProgramV1
      source s!"<soroban-{label}>" s!"Tests.Soroban{label}" none)
    match Compiler.compileValidatedSourceV1 parsed with
    | .error e =>
        expect (e.render.contains needle)
          s!"{label} compile FC must contain '{needle}', got: {e.render}"
        unless also.isEmpty do
          expect (e.render.contains also)
            s!"{label} compile FC must contain '{also}', got: {e.render}"
    | .ok compiled =>
        match planSoroban compiled with
        | .error e =>
            expect (e.render.contains needle)
              s!"{label} Plan FC must contain '{needle}', got: {e.render}"
            unless also.isEmpty do
              expect (e.render.contains also)
                s!"{label} Plan FC must contain '{also}', got: {e.render}"
        | .ok _ =>
            throw <| IO.userError
              s!"{label} must compile-or-Plan fail closed"
  let bytesBody (qn : String) : String :=
    "  state pad : UInt64\n" ++
      "  state data : Bytes 4\n" ++
      "  init() do\n" ++
      "    pad := 0\n" ++
      "    data[0] := 1\n" ++
      "  entry probe() : UInt64 do\n" ++
      "    let h : UInt256 := call " ++ qn ++ "(data)\n" ++
      "    return pad\n" ++
      "  view get() : UInt64 do\n" ++
      "    return pad\n"
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program Sha256BytesSoroban where\n" ++
    bytesBody "pf.crypto.sha256Bytes"
  let parsed ← liftResult (← session.selectProgramV1
    source "<soroban-sha256-bytes>" "Tests.SorobanSha256Bytes" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planSoroban compiled
  let some probe := plan.entries.find? (·.name == "probe") |
    throw <| IO.userError "Sha256BytesSoroban: missing probe entry"
  expect (probe.sha256Sites.size == 0)
    "Sha256BytesSoroban: must not reuse the CAP-4 UInt256 sha256Sites record"
  expect (probe.sha256BytesSites.size == 1)
    "Sha256BytesSoroban: plan must record exactly one sha256Bytes site"
  let some site := probe.sha256BytesSites[0]? |
    throw <| IO.userError "Sha256BytesSoroban: missing sha256Bytes site"
  expect (site.byteLen == 4 && site.bytes.size == 4)
    s!"Sha256BytesSoroban: site must carry 4 Bytes leaves, got {site.byteLen}/{site.bytes.size}"
  liftResult <| Targets.Soroban.validatePlan plan
  let files ← liftResult <| buildSoroban compiled
  let some rsFile := files.find? (fun f => f.path == "Sha256BytesSoroban.rs") |
    throw <| IO.userError "soroban: missing Sha256BytesSoroban.rs"
  let rs := rsFile.contents
  expect (rs.contains "env.crypto().sha256")
    "Soroban sha256Bytes source must call env.crypto().sha256"
  expect (rs.contains "soroban_sdk::Bytes::from_array")
    "Soroban sha256Bytes source must construct soroban_sdk::Bytes from N low-8 leaves"
  expect (rs.contains "pf_sha256b_0")
    "Soroban sha256Bytes source must use the independent Bytes-site name prefix"
  expect (!rs.contains "pf_sha256_0_bytes")
    "Soroban sha256Bytes source must not emit the CAP-4 UInt256 limb packer"
  expect (rs.contains "ProofForge Soroban S0")
    "sha256Bytes source must stay an S0 recipe"
  let selection ← liftResult <|
    Targets.BuildSelectionV1.resolveBuildSelectionV1 TargetId.soroban none
  let capability ← liftResult <|
    Targets.resolveEngineeringRequirementsV1 selection compiled
  let artifacts ← liftResult <| Targets.materializeResult capability
  let finalized ← Targets.finalizeMaterializedArtifactsV1
    capability artifacts (System.FilePath.mk ".")
  expect (!FinalizedArtifactsV1.deployableOf finalized)
    "sha256Bytes must not make Soroban S0 deployable"
  expect (FinalizedArtifactsV1.extraFilesOf finalized).isEmpty
    "sha256Bytes must not grow S0 Finalize beyond zero-tool"
  -- Sibling / near-miss QNs keep the CAP-4 host-binding envelope (UInt256
  -- operand so they reach Plan rather than the shared-core integer-arg gate).
  let siblingBody (qn : String) : String :=
    "  state pad : UInt64\n" ++
      "  init() do\n" ++
      "    pad := 0\n" ++
      "  entry probe() : UInt64 do\n" ++
      "    let w : UInt256 := 0\n" ++
      "    let h : UInt256 := call " ++ qn ++ "(w)\n" ++
      "    return pad\n" ++
      "  view get() : UInt64 do\n" ++
      "    return pad\n"
  expectPlanFc "Keccak256BytesSoroban" (siblingBody "pf.crypto.keccak256")
    "has no Soroban host binding" "keccak256"
  expectPlanFc "Sha256BytesHashNoPad"
    (siblingBody "pf.crypto.hashNoPad")
    "has no Soroban host binding"
  expectPlanFc "Sha256BytesSibling"
    (siblingBody "pf.crypto.sha256Bytess")
    "has no Soroban host binding" "sha256Bytess"
  expectPlanFc "Sha256BytesU64"
    ("  state pad : UInt64\n" ++
      "  init() do\n" ++
      "    pad := 0\n" ++
      "  entry probe() : UInt64 do\n" ++
      "    let w : UInt64 := 0\n" ++
      "    let h : UInt256 := call pf.crypto.sha256Bytes(w)\n" ++
      "    return pad\n" ++
      "  view get() : UInt64 do\n" ++
      "    return pad\n")
    "pf.crypto.sha256Bytes" "Bytes"
  expectPlanFc "Sha256BytesZeroArg"
    ("  state pad : UInt64\n" ++
      "  init() do\n" ++
      "    pad := 0\n" ++
      "  entry probe() : UInt64 do\n" ++
      "    let h : UInt256 := call pf.crypto.sha256Bytes()\n" ++
      "    return pad\n" ++
      "  view get() : UInt64 do\n" ++
      "    return pad\n")
    "pf.crypto.sha256Bytes"
  expectPlanFc "Sha256BytesTwoArg"
    ("  state pad : UInt64\n" ++
      "  state data : Bytes 4\n" ++
      "  init() do\n" ++
      "    pad := 0\n" ++
      "    data[0] := 1\n" ++
      "  entry probe() : UInt64 do\n" ++
      "    let h : UInt256 := call pf.crypto.sha256Bytes(data, data)\n" ++
      "    return pad\n" ++
      "  view get() : UInt64 do\n" ++
      "    return pad\n")
    "pf.crypto.sha256Bytes"
  expectPlanFc "Sha256BytesResU64"
    ("  state data : Bytes 4\n" ++
      "  init() do\n" ++
      "    data[0] := 1\n" ++
      "  entry probe() : UInt64 do\n" ++
      "    return call pf.crypto.sha256Bytes(data)\n" ++
      "  view get() : UInt64 do\n" ++
      "    return 0\n")
    "pf.crypto.sha256Bytes" "UInt256"
  expectPlanFc "Sha256BytesN9"
    ("  state pad : UInt64\n" ++
      "  init() do\n" ++
      "    pad := 0\n" ++
      "  entry probe(b : Bytes 9) : UInt64 do\n" ++
      "    let h : UInt256 := call pf.crypto.sha256Bytes(b)\n" ++
      "    return pad\n" ++
      "  view get() : UInt64 do\n" ++
      "    return pad\n")
    "1..8" "9"
  expectPlanFc "Sha256BytesView"
    ("  state data : Bytes 4\n" ++
      "  init() do\n" ++
      "    data[0] := 1\n" ++
      "  view peek() : UInt64 do\n" ++
      "    let h : UInt256 := call pf.crypto.sha256Bytes(data)\n" ++
      "    return 0\n")
    "view" "external.call.sync"

/-- CAP-3 / CAP-D-SOR-LEDGER: S0 source-only Plan admits
    `context.unixTimeSeconds` → `env.ledger().timestamp()` and
    `context.blockHeight` → `env.ledger().sequence()` (u32 widened to u64).
    Ledger reads are available in any Soroban invocation, and every S0
    contract fn already receives `env: Env`, so init/entry/view all admit.
    Finalize stays zero-tool / non-deployable. -/
unsafe def testLedgerContextReadAdmitted : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program LedgerReads where\n" ++
    "  state t : UInt64\n" ++
    "  state h : UInt64\n" ++
    "  init() do\n" ++
    "    t := context.unixTimeSeconds\n" ++
    "    h := context.blockHeight\n" ++
    "  entry now() : UInt64 do\n" ++
    "    return context.unixTimeSeconds\n" ++
    "  entry height() : UInt64 do\n" ++
    "    return context.blockHeight\n" ++
    "  view peekTime() : UInt64 do\n" ++
    "    return context.unixTimeSeconds\n" ++
    "  view peekHeight() : UInt64 do\n" ++
    "    return context.blockHeight\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<soroban-ledger-reads>" "Tests.SorobanLedgerReads" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planSoroban compiled
  let some initFn := plan.initializer |
    throw <| IO.userError "LedgerReads must have an initializer"
  let initStoresUnix :=
    initFn.stores.any (fun s =>
      match s with
      | (0, .unixTimeSeconds) => true
      | _ => false)
  let initStoresHeight :=
    initFn.stores.any (fun s =>
      match s with
      | (1, .blockHeight) => true
      | _ => false)
  expect initStoresUnix "init must store unixTimeSeconds into t"
  expect initStoresHeight "init must store blockHeight into h"
  let some now := plan.entries.find? (·.name == "now") |
    throw <| IO.userError "missing now entry"
  expect (now.result? == some .unixTimeSeconds)
    "entry now must return unixTimeSeconds"
  let some height := plan.entries.find? (·.name == "height") |
    throw <| IO.userError "missing height entry"
  expect (height.result? == some .blockHeight)
    "entry height must return blockHeight"
  let some peekTime := plan.views.find? (·.name == "peekTime") |
    throw <| IO.userError "missing peekTime view"
  expect (peekTime.value == .unixTimeSeconds)
    "view peekTime must return unixTimeSeconds"
  let some peekHeight := plan.views.find? (·.name == "peekHeight") |
    throw <| IO.userError "missing peekHeight view"
  expect (peekHeight.value == .blockHeight)
    "view peekHeight must return blockHeight"
  liftResult <| Targets.Soroban.validatePlan plan
  let files ← liftResult <| buildSoroban compiled
  let some rsFile := files.find? (fun f => f.path == "LedgerReads.rs") |
    throw <| IO.userError "soroban: missing LedgerReads.rs"
  let rs := rsFile.contents
  expect (rs.contains "env.ledger().timestamp()")
    "Soroban source must read env.ledger().timestamp() for unixTimeSeconds"
  expect (rs.contains "env.ledger().sequence()")
    "Soroban source must read env.ledger().sequence() for blockHeight"
  expect (rs.contains "u64::from(env.ledger().sequence())")
    "Soroban source must widen sequence() u32 to u64"
  expect (rs.contains "pub fn init(env: Env)")
    "init must keep env: Env (ledger reads use it)"
  expect (rs.contains "pub fn now(env: Env)")
    "entry now must keep env: Env"
  expect (rs.contains "pub fn peekTime(env: Env)")
    "view peekTime must keep env: Env"
  expect (rs.contains "ProofForge Soroban S0")
    "ledger-read source must stay an S0 recipe"
  let selection ← liftResult <|
    Targets.BuildSelectionV1.resolveBuildSelectionV1 TargetId.soroban none
  let capability ← liftResult <|
    Targets.resolveEngineeringRequirementsV1 selection compiled
  let artifacts ← liftResult <| Targets.materializeResult capability
  let finalized ← Targets.finalizeMaterializedArtifactsV1
    capability artifacts (System.FilePath.mk ".")
  expect (!FinalizedArtifactsV1.deployableOf finalized)
    "ledger reads must not make Soroban S0 deployable"
  expect (FinalizedArtifactsV1.extraFilesOf finalized).isEmpty
    "ledger reads must not grow S0 Finalize beyond zero-tool"

/-- SYS-S4 residual after CAP-3: attachedValue/chainId stay Plan fail closed.
    caller/self are Principal and stay on the generic ContextRead envelope
    (S0 rejects Principal at type closure first). -/
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

/-- Array *entry* return stays fail closed (view aggregate is T6). -/
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
    source "<soroban-arr-ret>" "Tests.SorobanArrRetBox" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planSoroban compiled
  let some e := plan.entries[0]? |
    throw <| IO.userError "ArrRetBox must emit an entry"
  expect (e.resultKind == .aggregate 2)
    s!"ArrRetBox entry must be aggregate 2, got {repr e.resultKind}"
  liftResult <| Targets.Soroban.validatePlan plan
  let files ← liftResult <| buildSoroban compiled
  expect (!files.isEmpty) "ArrRetBox must emit nonempty files"
  let some rs := files.find? (·.path == "ArrRetBox.rs") |
    throw <| IO.userError "soroban: missing ArrRetBox.rs"
  expect (rs.contents.contains "-> (u64, u64)")
    "ArrRetBox must emit a Rust u64 tuple return"

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
    source "<soroban-opt-ret>" "Tests.SorobanOptRetBox" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planSoroban compiled
  let some e := plan.entries[0]? |
    throw <| IO.userError "OptRetBox must emit an entry"
  expect (e.resultKind == .aggregate 2)
    s!"OptRetBox entry must be aggregate 2, got {repr e.resultKind}"
  liftResult <| Targets.Soroban.validatePlan plan
  let files ← liftResult <| buildSoroban compiled
  expect (!files.isEmpty) "OptRetBox must emit nonempty files"
  let some rs := files.find? (·.path == "OptRetBox.rs") |
    throw <| IO.userError "soroban: missing OptRetBox.rs"
  expect (rs.contents.contains "-> (u64, u64)")
    "OptRetBox must emit a Rust u64 tuple return"

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
    source "<soroban-maybe-ret>" "Tests.SorobanMaybeRetBox" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planSoroban compiled
  let some e := plan.entries[0]? |
    throw <| IO.userError "MaybeRetBox must emit an entry"
  expect (e.resultKind == .aggregate 2)
    s!"MaybeRetBox entry must be aggregate 2, got {repr e.resultKind}"
  liftResult <| Targets.Soroban.validatePlan plan
  let files ← liftResult <| buildSoroban compiled
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
    source "<soroban-pair-ret-entry>" "Tests.SorobanPairRetEntry" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planSoroban compiled
  let some e := plan.entries[0]? |
    throw <| IO.userError "PairRetEntry must emit an entry"
  expect (e.resultKind == .aggregate 2)
    s!"PairRetEntry entry must be aggregate 2, got {repr e.resultKind}"
  liftResult <| Targets.Soroban.validatePlan plan
  let files ← liftResult <| buildSoroban compiled
  expect (!files.isEmpty) "PairRetEntry must emit nonempty files"

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

/-- B-RET-MAP: Map return is 24 leaves, not an 8-leaf cap raise. -/
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
  let plan ← liftResult <| planSoroban compiled
  let some ent := plan.entries[0]? |
    throw <| IO.userError "MapRet must emit an entry"
  expect (ent.resultKind == .aggregate 24)
    s!"MapRet entry must be aggregate 24, got {repr ent.resultKind}"
  expect (ent.leaves.size == 24) "MapRet must carry 24 Map leaves"
  liftResult <| Targets.Soroban.validatePlan plan
  let files ← liftResult <| buildSoroban compiled
  let some rs := files.find? (·.path == "MapRet.rs") |
    throw <| IO.userError "soroban: missing MapRet.rs"
  expect (rs.contents.contains "-> (u64, u64, u64, u64, u64, u64, u64, u64, u64, u64, u64, u64, u64, u64, u64, u64, u64, u64, u64, u64, u64, u64, u64, u64)")
    "MapRet must emit a Rust 24-u64 tuple return"
  expect (rs.contents.contains "symbol_short!(\"m_0\")")
    "MapRet.rs must use instance key m_0"
  expect (rs.contents.contains "symbol_short!(\"m_23\")")
    "MapRet.rs must use instance key m_23"

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
    source "<soroban-arr-int64-ret>" "Tests.SorobanArrInt64Ret" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planSoroban compiled
  expect plan.signedNumeric "ArrInt64Ret Plan is signed"
  let some e := plan.entries[0]? |
    throw <| IO.userError "ArrInt64Ret must emit an entry"
  expect (e.resultKind == .aggregate 2)
    s!"ArrInt64Ret entry must be aggregate 2, got {repr e.resultKind}"
  expect (e.leafIsInt == #[true, true]) "ArrInt64Ret leaves must be signed"
  liftResult <| Targets.Soroban.validatePlan plan
  let files ← liftResult <| buildSoroban compiled
  let some rs := files.find? (·.path == "ArrInt64Ret.rs") |
    throw <| IO.userError "soroban: missing ArrInt64Ret.rs"
  expect (rs.contents.contains "-> (i64, i64)")
    "ArrInt64Ret must emit a Rust i64 tuple return"

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
    source "<soroban-opt-int64-ret>" "Tests.SorobanOptInt64Ret" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planSoroban compiled
  expect plan.signedNumeric "OptInt64Ret Plan is signed"
  let some e := plan.entries[0]? |
    throw <| IO.userError "OptInt64Ret must emit an entry"
  expect (e.resultKind == .aggregate 2)
    s!"OptInt64Ret entry must be aggregate 2, got {repr e.resultKind}"
  expect (e.leafIsInt == #[false, true])
    s!"OptInt64Ret leaves must be tag unsigned + payload isInt, got {e.leafIsInt}"
  liftResult <| Targets.Soroban.validatePlan plan

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
    source "<soroban-map-int64-ret>" "Tests.SorobanMapInt64Ret" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planSoroban compiled
  expect plan.signedNumeric "MapInt64Ret Plan is signed"
  let some e := plan.entries[0]? |
    throw <| IO.userError "MapInt64Ret must emit an entry"
  expect (e.resultKind == .aggregate 24)
    s!"MapInt64Ret entry must be aggregate 24, got {repr e.resultKind}"
  expect (e.leaves.size == 24) "MapInt64Ret must carry 24 Map leaves"
  expect ((List.range 24).all (fun i =>
      e.leafIsInt[i]! == (i % 3 == 2)))
    s!"MapInt64Ret val slots must be isInt, got {e.leafIsInt}"
  liftResult <| Targets.Soroban.validatePlan plan

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
  let planRet ← liftResult <| planSoroban compiledRet
  let some v := planRet.views[0]? |
    throw <| IO.userError "PrincipalReturn must emit a view"
  expect (v.resultKind == .aggregate 9)
    s!"PrincipalReturn view must be aggregate 9, got {repr v.resultKind}"
  liftResult <| Targets.Soroban.validatePlan planRet
  let strRetSource :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program StringReturn where\n" ++
    "  state label : String\n" ++
    "  init(initial : String) do\n" ++
    "    label := initial\n" ++
    "  view getLabel() : String do\n" ++
    "    return label\n"
  let parsedStr ← liftResult (← session.selectProgramV1
    strRetSource "<soroban-string-ret>" "Tests.SorobanStringReturn" none)
  let compiledStr ← liftResult <| Compiler.compileValidatedSourceV1 parsedStr
  let planStr ← liftResult <| planSoroban compiledStr
  let some sv := planStr.views[0]? |
    throw <| IO.userError "StringReturn must emit a view"
  expect (sv.resultKind == .aggregate 9)
    s!"StringReturn view must be aggregate 9, got {repr sv.resultKind}"
  liftResult <| Targets.Soroban.validatePlan planStr

unsafe def testConstStr : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program GreetingBox where\n" ++
    "  const GREETING : String := \"hi\"\n" ++
    "  state label : String\n" ++
    "  init() do\n" ++
    "    label := GREETING\n" ++
    "  view getLabel() : String do\n" ++
    "    return label\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<soroban-const-str>" "Tests.SorobanGreetingBox" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planSoroban compiled
  let some v := plan.views[0]? |
    throw <| IO.userError "GreetingBox must emit a view"
  expect (v.resultKind == .aggregate 9)
    s!"GreetingBox view must be aggregate 9, got {repr v.resultKind}"
  liftResult <| Targets.Soroban.validatePlan plan

unsafe def testStrMatch : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program StrMatch where\n" ++
    "  state pad : UInt64\n" ++
    "  init() do\n" ++
    "    pad := 0\n" ++
    "  entry classify(s : String) : UInt64 do\n" ++
    "    match s with\n" ++
    "    | \"a\" => do\n" ++
    "      return 1\n" ++
    "    | _ => do\n" ++
    "      return 0\n"
  let parsed ← liftResult (← session.selectProgramV1
    source "<soroban-str-match>" "Tests.SorobanStrMatch" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planSoroban compiled
  let some e := plan.entries[0]? |
    throw <| IO.userError "StrMatch must emit classify"
  expect (e.name == "classify") "StrMatch entry must be classify"
  liftResult <| Targets.Soroban.validatePlan plan

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
    source "<soroban-point-box>" "Tests.SorobanPointBox" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planSoroban compiled
  expect (plan.states.map (·.name) == #["p_x", "p_y"])
    "PointBox must flatten to p_x/p_y"
  liftResult <| Targets.Soroban.validatePlan plan
  let files ← liftResult <| buildSoroban compiled
  expect (!files.isEmpty) "PointBox must materialize files"

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
    source "<soroban-maybe-mark>" "Tests.SorobanMaybeMark" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planSoroban compiled
  expect (plan.states.map (·.name) == #["m_tag", "m_p0"])
    "MaybeMark must flatten to m_tag/m_p0"
  liftResult <| Targets.Soroban.validatePlan plan
  let files ← liftResult <| buildSoroban compiled
  expect (!files.isEmpty) "MaybeMark must materialize files"

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
    source "<soroban-arr-view-ret>" "Tests.SorobanArrViewRet" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planSoroban compiled
  let some v := plan.views[0]? |
    throw <| IO.userError "ArrViewRet must emit a view"
  expect (v.resultKind == .aggregate 2)
    s!"ArrViewRet view must be aggregate 2, got {repr v.resultKind}"
  liftResult <| Targets.Soroban.validatePlan plan
  let files ← liftResult <| buildSoroban compiled
  expect (!files.isEmpty) "ArrViewRet must emit nonempty files"
  let some rs := files.find? (·.path == "ArrViewRet.rs") |
    throw <| IO.userError "soroban: missing ArrViewRet.rs"
  expect (rs.contents.contains "-> (u64, u64)")
    "ArrViewRet must emit a Rust u64 tuple return"

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
    source "<soroban-bytes-view-ret>" "Tests.SorobanBytesRetBox" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planSoroban compiled
  let some v := plan.views[0]? |
    throw <| IO.userError "BytesRetBox must emit a view"
  expect (v.resultKind == .aggregate 4)
    s!"BytesRetBox view must be aggregate 4, got {repr v.resultKind}"
  liftResult <| Targets.Soroban.validatePlan plan
  let files ← liftResult <| buildSoroban compiled
  let some rs := files.find? (·.path == "BytesRetBox.rs") |
    throw <| IO.userError "soroban: missing BytesRetBox.rs"
  expect (rs.contents.contains "-> (u64, u64, u64, u64)")
    "BytesRetBox must emit a Rust 4-u64 tuple return"
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
    entrySrc "<soroban-bytes-entry-ret>" "Tests.SorobanBytesRetEntry" none)
  let entryCompiled ← liftResult <| Compiler.compileValidatedSourceV1 entryParsed
  let entryPlan ← liftResult <| planSoroban entryCompiled
  let some ent := entryPlan.entries[0]? |
    throw <| IO.userError "BytesRetEntry must emit an entry"
  expect (ent.resultKind == .aggregate 4)
    s!"BytesRetEntry entry must be aggregate 4, got {repr ent.resultKind}"
  liftResult <| Targets.Soroban.validatePlan entryPlan
  let entryFiles ← liftResult <| buildSoroban entryCompiled
  let some entryRs := entryFiles.find? (·.path == "BytesRetEntry.rs") |
    throw <| IO.userError "soroban: missing BytesRetEntry.rs"
  expect (entryRs.contents.contains "-> (u64, u64, u64, u64)")
    "BytesRetEntry must emit a Rust 4-u64 tuple return"

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
    source "<soroban-bytes-param>" "Tests.SorobanBytesParam" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planSoroban compiled
  let some ent := plan.entries[0]? |
    throw <| IO.userError "BytesParam must emit an entry"
  expect (ent.params == #["b_0", "b_1"])
    s!"BytesParam must flatten to b_0/b_1, got {ent.params}"
  liftResult <| Targets.Soroban.validatePlan plan
  let files ← liftResult <| buildSoroban compiled
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
    source "<soroban-opt-param>" "Tests.SorobanOptParam" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planSoroban compiled
  let some ent := plan.entries[0]? |
    throw <| IO.userError "OptParam must emit an entry"
  expect (ent.params == #["o_tag", "o_p0"])
    s!"OptParam must flatten to o_tag/o_p0, got {ent.params}"
  liftResult <| Targets.Soroban.validatePlan plan

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
    source "<soroban-arr-param>" "Tests.SorobanArrParam" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planSoroban compiled
  let some ent := plan.entries[0]? |
    throw <| IO.userError "ArrParam must emit an entry"
  expect (ent.params == #["a_0", "a_1"])
    s!"ArrParam must flatten to a_0/a_1, got {ent.params}"
  liftResult <| Targets.Soroban.validatePlan plan

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
    source "<soroban-map-param>" "Tests.SorobanMapParam" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planSoroban compiled
  let some ent := plan.entries[0]? |
    throw <| IO.userError "MapParam must emit an entry"
  let expected := (List.range 24).toArray.map (fun i => s!"m_{i}")
  expect (ent.params == expected)
    s!"MapParam must flatten to 24 occ/key/val leaves, got {ent.params}"
  liftResult <| Targets.Soroban.validatePlan plan

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
    source "<soroban-opt-view-ret>" "Tests.SorobanOptViewRet" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planSoroban compiled
  let some v := plan.views[0]? |
    throw <| IO.userError "OptViewRet must emit a view"
  expect (v.resultKind == .aggregate 2)
    s!"OptViewRet view must be aggregate 2, got {repr v.resultKind}"
  liftResult <| Targets.Soroban.validatePlan plan
  let files ← liftResult <| buildSoroban compiled
  expect (!files.isEmpty) "OptViewRet must emit nonempty files"
  let some rs := files.find? (·.path == "OptViewRet.rs") |
    throw <| IO.userError "soroban: missing OptViewRet.rs"
  expect (rs.contents.contains "-> (u64, u64)")
    "OptViewRet must emit a Rust u64 tuple return"

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
    source "<soroban-point-view-ret>" "Tests.SorobanPointViewRet" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planSoroban compiled
  let some v := plan.views[0]? |
    throw <| IO.userError "PointViewRet must emit a view"
  expect (v.resultKind == .aggregate 2)
    s!"PointViewRet view must be aggregate 2, got {repr v.resultKind}"
  liftResult <| Targets.Soroban.validatePlan plan
  let files ← liftResult <| buildSoroban compiled
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
    source "<soroban-maybe-view-ret>" "Tests.SorobanMaybeViewRet" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planSoroban compiled
  let some v := plan.views[0]? |
    throw <| IO.userError "MaybeViewRet must emit a view"
  expect (v.resultKind == .aggregate 2)
    s!"MaybeViewRet view must be aggregate 2, got {repr v.resultKind}"
  liftResult <| Targets.Soroban.validatePlan plan
  let files ← liftResult <| buildSoroban compiled
  expect (!files.isEmpty) "MaybeViewRet must emit nonempty files"

/-- T9a: if-diamond only. BranchFlow.apply (match/switch) stays fail closed. -/
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
    source "<soroban-if-flow>" "Tests.SorobanIfFlow" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planSoroban compiled
  let some bump := plan.entries.find? (·.name == "bump") |
    throw <| IO.userError "IfFlow: missing bump"
  expect (bump.stores.isEmpty && bump.result?.isNone)
    "IfFlow bump must use CFG body, not flat stores/result?"
  expect (bump.body == #[
      .ifThenElse (.compare .gt (.stateLoad 0) (.litU64 0))
        #[.store 0 (.arith .add (.stateLoad 0) (.param 0))]
        #[.store 0 (.param 0)],
      .returnValue (.stateLoad 0)])
    "IfFlow bump must lower the branch diamond then join return"
  liftResult <| Targets.Soroban.validatePlan plan
  let files ← liftResult <| buildSoroban compiled
  let some rsFile := files.find? (fun f => f.path == "IfFlow.rs") |
    throw <| IO.userError "IfFlow: missing IfFlow.rs"
  expect (rsFile.contents.contains "if ")
    "IfFlow Rust must render an if"
  IO.println "  ✓ IfFlow if-diamond"

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
    source "<soroban-branch-flow>" "Tests.SorobanBranchFlow" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planSoroban compiled
  let some apply := plan.entries.find? (·.name == "apply") |
    throw <| IO.userError "BranchFlow: missing apply"
  let hasSwitch :=
    apply.body.any fun s =>
      match s with
      | .switchOn _ cases _ =>
          cases.any (fun (v, _) => v == 0) && cases.any (fun (v, _) => v == 1)
      | _ => false
  expect hasSwitch "BranchFlow apply must lower match to switchOn"
  liftResult <| Targets.Soroban.validatePlan plan
  let files ← liftResult <| buildSoroban compiled
  let some rsFile := files.find? (fun f => f.path == "BranchFlow.rs") |
    throw <| IO.userError "BranchFlow: missing BranchFlow.rs"
  expect (rsFile.contents.contains "if ")
    "BranchFlow Rust must render the switch as an if-chain"
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
    source "<soroban-maybe-match>" "Tests.SorobanMaybeMatch" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planSoroban compiled
  let some take := plan.entries.find? (·.name == "take") |
    throw <| IO.userError "MaybeMatch: missing take"
  let hasSwitch :=
    take.body.any fun s =>
      match s with
      | .switchOn _ cases _ =>
          cases.any (fun (v, _) => v == 0) || cases.any (fun (v, _) => v == 1)
      | _ => false
  expect hasSwitch "MaybeMatch take must switch on the Option tag leaf"
  liftResult <| Targets.Soroban.validatePlan plan
  IO.println "  ✓ MaybeMatch Option tag switch"

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
    source "<soroban-loop-sum>" "Tests.SorobanLoopSum" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 parsed
  let plan ← liftResult <| planSoroban compiled
  let some addUp := plan.entries.find? (·.name == "addUp") |
    throw <| IO.userError "LoopSum: missing addUp"
  let hasFor :=
    addUp.body.any fun s =>
      match s with
      | .forLoop _ _ _ _ maxIt _ => maxIt == 8
      | _ => false
  expect hasFor "LoopSum addUp must lower bounded-for to forLoop max=8"
  liftResult <| Targets.Soroban.validatePlan plan
  let files ← liftResult <| buildSoroban compiled
  let some rsFile := files.find? (fun f => f.path == "LoopSum.rs") |
    throw <| IO.userError "LoopSum: missing LoopSum.rs"
  expect (rsFile.contents.contains "loop {" &&
      rsFile.contents.contains "loop bound exceeded" &&
      !rsFile.contents.contains "while true")
    "LoopSum Rust must render a counted loop trap, not an unbounded while"
  IO.println "  ✓ LoopSum bounded-for"

unsafe def run : IO Unit := do
  testStateCellSorobanSource
  testInt64CellSorobanSource
  testMixedInt64UInt64Fc
  testMultiWidthFailClosed
  testInvariantFailClosed
  testCallFailClosed
  testCryptoSha256Admitted
  testCryptoSha256BytesAdmitted
  testLedgerContextReadAdmitted
  testContextReadStayFailClosed
  testEnvReadNativeStayFailClosed
  testCapabilityProductPath
  testUnknownProfileFailClosed
  testArrayBoxFlatten
  testArrInt64Flatten
  testArrayN9FailClosed
  testArrayInt64N9FailClosed
  testArrayNonUInt64ElementFailClosed
  testArrRetBox
  testArrayInt64Return
  testOptionInt64Return
  testMapInt64Return
  testSignedNumericArrayStateFailClosed
  testArrayLongNameSymbolShortFailClosed
  testOptBoxAdmit
  testOptInt64Flatten
  testOptionInt64ElementFailClosed
  testOptRetBox
  testMaybeRetBox
  testPairRetEntry
  testSignedNumericOptionStateFailClosed
  testMapMiniAdmit
  testMapInt64Flatten
  testMapInt64ElementFailClosed
  testMapReturnFailClosed
  testSignedNumericMapStateFailClosed
  testPrincipalIdentityLeaves
  testConstStr
  testStrMatch
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
  testIfFlow
  testBranchFlow
  testMaybeMatch
  testLoopSum
  IO.println "Tests.Materialization.SorobanPlanV1: ok"

end Tests.Materialization.SorobanPlanV1
