import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Core.Crypto
import ProofForgeV2.Examples.StateCell
import ProofForgeV2.Language.Loader
import ProofForgeV2.Targets.Registry
import ProofForgeV2.Targets.BuildSelectionV1
import ProofForgeV2.Targets.RequirementResolverV1
import ProofForgeV2.Semantic.RequirementsV1
import ProofForgeV2.Semantic.WireV1
import Tests.Language.ParserSession

namespace Tests.Materialization

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Core.Common
open ProofForgeV2.Targets.BuildSelectionV1
open ProofForgeV2.Targets.RequirementResolverV1
open ProofForgeV2.Semantic.RequirementsV1
open ProofForgeV2.Semantic.WireV1

private def zeroDigest : Digest :=
  { algorithm := .sha256, bytes := ByteArray.mk (Array.replicate 32 0) }

private def parseProfileFixture (s : String) : IO CodegenProfileId :=
  match CodegenProfileId.parse? s with
  | some id => pure id
  | none => throw <| IO.userError s!"test fixture profile failed grammar: '{s}'"

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def liftResult (result : CompileResult α) : IO α :=
  match result with
  | .ok value => pure value
  | .error error => throw <| IO.userError error.render

/-- Product aggregate path: selection → resolveEngineeringRequirementsV1 → capability. -/
private def materializeSelected (target : TargetId) (compiled : CompiledSemanticV1)
    (profile? : Option CodegenProfileId := none) : CompileResult MaterializedArtifactsV1 := do
  let selection ← resolveBuildSelectionV1 target profile?
  let capability ← Targets.resolveEngineeringRequirementsV1 selection compiled
  Targets.materializeResult capability

private def expectContextMatrixAdmit
    (label : String) (target : TargetId) (compiled : CompiledSemanticV1) : IO Unit := do
  match materializeSelected target compiled with
  | .ok _ => pure ()
  | .error e =>
      throw <| IO.userError s!"{label}: {target} must admit, got {e.render}"

private def expectContextMatrixFailClosed
    (label : String) (target : TargetId) (kind : TargetKind)
    (expectedMessage : String) (compiled : CompiledSemanticV1) : IO Unit := do
  match materializeSelected target compiled with
  | .error (.planInvariant gotKind message) =>
      expect (gotKind == kind)
        s!"{label}: expected planInvariant target {kind}, got {gotKind}"
      expect (message == expectedMessage)
        s!"{label}: exact planInvariant message mismatch; got '{message}'"
  | .error e =>
      throw <| IO.userError
        s!"{label}: expected planInvariant {kind}, got {e.render}"
  | .ok _ =>
      throw <| IO.userError s!"{label}: {target} must fail closed"

/-- Capability-gated plan for the single retained-semantic compiled carrier. -/
private def planEvm (compiled : CompiledSemanticV1) : CompileResult Targets.Evm.Plan := do
  let selection ← resolveBuildSelectionV1 TargetId.evm none
  let capability ← Targets.resolveEngineeringRequirementsV1 selection compiled
  Targets.Evm.planFromCapability capability

/-- Sole-rail helper: inspect the product full-body Solana Plan used by the
    active `solana-sbpf-cpi-elf-v1` synthesis path. -/
private def planSolana (compiled : CompiledSemanticV1) : CompileResult Targets.Solana.Plan := do
  let selection ← resolveBuildSelectionV1 TargetId.solana none
  let capability ← Targets.resolveEngineeringRequirementsV1 selection compiled
  Targets.Solana.materializeFullBodyPlanForProductV1 capability false

private def planNear (compiled : CompiledSemanticV1) : CompileResult Targets.Near.Plan := do
  let selection ← resolveBuildSelectionV1 TargetId.near none
  let capability ← Targets.resolveEngineeringRequirementsV1 selection compiled
  Targets.Near.planFromCapability capability

private def planNoir (compiled : CompiledSemanticV1) : CompileResult Targets.Noir.Plan := do
  let selection ← resolveBuildSelectionV1 TargetId.noir none
  let capability ← Targets.resolveEngineeringRequirementsV1 selection compiled
  Targets.Noir.planFromCapability capability

private def planPsy (compiled : CompiledSemanticV1) : CompileResult Targets.Psy.Plan := do
  let selection ← resolveBuildSelectionV1 TargetId.psy none
  let capability ← Targets.resolveEngineeringRequirementsV1 selection compiled
  Targets.Psy.planFromCapability capability

private def planAleo (compiled : CompiledSemanticV1) : CompileResult Targets.Aleo.Plan := do
  let selection ← resolveBuildSelectionV1 TargetId.aleo none
  let capability ← Targets.resolveEngineeringRequirementsV1 selection compiled
  Targets.Aleo.planFromCapability capability

/-- Capability-gated production IR inspection (S6 repair; not TargetIrFixtures). -/
private def irEvm (compiled : CompiledSemanticV1) : CompileResult Targets.Evm.IR := do
  let selection ← resolveBuildSelectionV1 TargetId.evm none
  let capability ← Targets.resolveEngineeringRequirementsV1 selection compiled
  Targets.Evm.irFromCapability capability

/-- Sole-rail helper: inspect the product full-body Solana IR used by the
    active `solana-sbpf-cpi-elf-v1` synthesis path. -/
private def irSolana (compiled : CompiledSemanticV1) : CompileResult Targets.Solana.IR := do
  let selection ← resolveBuildSelectionV1 TargetId.solana none
  let capability ← Targets.resolveEngineeringRequirementsV1 selection compiled
  Targets.Solana.fullBodyIrFromProductCapabilityV1 capability false

private def irNear (compiled : CompiledSemanticV1) : CompileResult Targets.Near.IR := do
  let selection ← resolveBuildSelectionV1 TargetId.near none
  let capability ← Targets.resolveEngineeringRequirementsV1 selection compiled
  Targets.Near.irFromCapability capability

private def irNoir (compiled : CompiledSemanticV1) : CompileResult Targets.Noir.IR := do
  let selection ← resolveBuildSelectionV1 TargetId.noir none
  let capability ← Targets.resolveEngineeringRequirementsV1 selection compiled
  Targets.Noir.irFromCapability capability

/-- Independent fixed complete-byte evidence for capability Accumulator NEAR WAT
    (UTF-8 length + SHA-256 of real materializeResult bytes; not a reimplemented
    renderer). Trailing newline is part of the hashed bytes. Wave D: the two new
    host imports (log_utf8/panic_utf8) extend every method's WAT by exactly two
    import lines. -/
private def accumulatorNearWatExactUtf8Len : Nat := 5050
private def accumulatorNearWatSha256Hex : String :=
  "a22f301f9de41312b7c3cc6f5bc5ca4ab0bdada7ed85c68ea354cbb39b7c32b8"

/-- Independent fixed exact complete Noir add relation source for capability
    Accumulator (full string golden; trailing newline included). -/
private def accumulatorNoirAddExactSource : String :=
  "fn main(pre_initialized: pub bool, pre_s0: pub u64, arg_p0: pub u64, post_s0: pub u64, post_initialized: pub bool, result: pub u64) {\n" ++
  "    assert(pre_initialized == true);\n" ++
  "    let t0: u64 = pre_s0 + arg_p0;\n" ++
  "    assert(post_s0 == t0);\n" ++
  "    assert(post_initialized == true);\n" ++
  "    assert(result == t0);\n" ++
  "}\n"

/-- ProgramV1 Accumulator source text for capability materialize goldens. -/
private def accumulatorSourceTextV1 : String :=
  "import ProofForgeV2\n\n" ++
  "namespace ProofForgeV2.Examples\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program Accumulator where\n" ++
  "  state total : UInt64\n\n" ++
  "  init(seed : UInt64) do\n" ++
  "    total := seed\n\n" ++
  "  entry add(amount : UInt64) : UInt64 do\n" ++
  "    total := total + amount\n" ++
  "    return total\n\n" ++
  "  view current() : UInt64 do\n" ++
  "    return total\n\n" ++
  "end ProofForgeV2.Examples\n"

private def accumulatorModuleNameV1 : String := "Examples.Accumulator"

private def richUInt64SourceTextV1 : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n" ++
  "program Ledger where\n" ++
  "  state left : UInt64\n" ++
  "  state right : UInt64\n" ++
  "  init(a : UInt64, b : UInt64) do\n" ++
  "    left := a\n" ++
  "    right := b\n" ++
  "  entry mix(x : UInt64, y : UInt64) : UInt64 do\n" ++
  "    left := left + x - y\n" ++
  "    right := right - x\n" ++
  "    return left\n" ++
  "  view getRight() : UInt64 do\n" ++
  "    return right\n"

private def constTargetBoundarySourceTextV1 : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n" ++
  "program ConstTargetBoundary where\n" ++
  "  const ANSWER : UInt64 := 42\n" ++
  "  state stored : UInt64\n" ++
  "  init() do\n" ++
  "    stored := 0\n" ++
  "  entry answer() : UInt64 do\n" ++
  "    stored := stored + ANSWER\n" ++
  "    return stored\n"

private def invariantTargetBoundarySourceTextV1 : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n" ++
  "program InvariantTargetBoundary where\n" ++
  "  entry tick() : UInt64 do\n" ++
  "    return 0\n" ++
  "  invariant truth : true\n"

private def stringInterfaceBoundarySourceTextV1 : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n" ++
  "program StringInterfaceBoundary where\n" ++
  "  event Note(message : String)\n" ++
  "  error Stop(reason : String)\n" ++
  "  entry emitNote() : UInt64 do\n" ++
  "    emit Note(\"hello\")\n" ++
  "    return 0\n" ++
  "  entry fail() : UInt64 do\n" ++
  "    revert Stop(\"stop\")\n"

private def intForBoundarySourceTextV1 : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n" ++
  "program IntForBoundary where\n" ++
  "  state total : Int64\n" ++
  "  init(initial : Int64) do\n" ++
  "    total := initial\n" ++
  "  entry iterate(start : Int64, stop : Int64) : Int64 do\n" ++
  "    for i in start ..< stop bounded 8 do\n" ++
  "      total := total + 1\n" ++
  "    return total\n"

private def anonymousResultBoundarySourceTextV1 : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n" ++
  "program AnonymousResultBoundary where\n" ++
  "  state slots : Array UInt64 2\n" ++
  "  init() do\n" ++
  "    slots[0] := 7\n" ++
  "    slots[1] := 9\n" ++
  "  view getArray() : Array UInt64 2 do\n" ++
  "    return slots\n"

private def expectMaterializePlanInvariantV1
    (label : String)
    (target : TargetId)
    (expectedKind : TargetKind)
    (compiled : CompiledSemanticV1)
    (marker : String) : IO Unit :=
  match materializeSelected target compiled with
  | .error (.planInvariant kind message) => do
      expect (kind == expectedKind)
        s!"{label}/{target}: expected plan target {expectedKind}, got {kind}"
      expect (message.contains marker)
        s!"{label}/{target}: expected marker '{marker}', got {message}"
  | .error error =>
      throw <| IO.userError
        s!"{label}/{target}: expected PF-PLAN-INVARIANT, got {error.render}"
  | .ok _ =>
      throw <| IO.userError
        s!"{label}/{target}: product materialization must fail closed"

/-- Normalize deliberately retains constants/invariants in the sole semantic
    carrier. Aleo and Psy own supported scalar Constant lowering; targets without
    that contract and all non-Quint invariant paths must still fail closed. -/
private unsafe def testConstInvariantMaterializationBoundary : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let constSource ← liftResult (← session.selectProgramV1
    constTargetBoundarySourceTextV1 "<targets-const-boundary>"
      "Tests.Targets.ConstTargetBoundary" none)
  let constCompiled ← liftResult <| Compiler.compileValidatedSourceV1 constSource
  let constData ← match validateSemanticProgramV1
      (CompiledSemanticV1.semanticV1Of constCompiled) with
    | .ok data => pure data
    | .error error =>
        throw <| IO.userError s!"const boundary: invalid semantic {repr error}"
  expect (constData.constants.size == 1)
    "const boundary: Normalize must retain one Constant row"
  expect (constData.callables.any (fun callable =>
      callable.blocks.any (fun block =>
        block.instructions.any (fun instruction =>
          match instruction.op with
          | .constant 0 => true
          | _ => false))))
    "const boundary: entry must retain Op.Constant 0"
  for (target, kind, marker) in #[
      (TargetId.evm, TargetKind.evm, "constants/invariants"),
      (TargetId.solana, TargetKind.solana, "constants/invariants"),
      (TargetId.noir, TargetKind.noir, "constants/invariants")] do
    expectMaterializePlanInvariantV1 "constant" target kind constCompiled marker
  -- NEAR admits scalar UInt/Int/Bool const table (inline as plan literals).
  let nearConstants ← liftResult <| materializeSelected TargetId.near constCompiled
  let nearFiles := MaterializedArtifactsV1.filesOf nearConstants
  expect (nearFiles.any (fun f => f.path.endsWith ".wat" || f.path.endsWith ".wasm"))
    s!"constant/near: scalar Op.Constant must materialize WAT/Wasm; got {nearFiles.map (·.path)}"
  -- CosmWasm admits the same scalar const table (plan literals → i64.const).
  let cwConstants ← liftResult <| materializeSelected TargetId.cosmwasm constCompiled
  let cwFiles := MaterializedArtifactsV1.filesOf cwConstants
  expect (cwFiles.any (fun f => f.path.endsWith ".wat" || f.path.endsWith ".wasm"))
    s!"constant/cosmwasm: scalar Op.Constant must materialize WAT/Wasm; got {cwFiles.map (·.path)}"
  let aleoConstants ← liftResult <| materializeSelected TargetId.aleo constCompiled
  let aleoFiles := MaterializedArtifactsV1.filesOf aleoConstants
  expect (aleoFiles.any (·.path == "consttargetboundary.aleo"))
    s!"constant/aleo: supported scalar Op.Constant must materialize to Aleo Instructions; got {aleoFiles.map (·.path)}"
  let psyConstants ← liftResult <| materializeSelected TargetId.psy constCompiled
  let psyFiles := MaterializedArtifactsV1.filesOf psyConstants
  expect (psyFiles.any (·.path == "ConstTargetBoundary.dpn.json"))
    s!"constant/psy: supported scalar Op.Constant must materialize to a Psy DPN package; got {psyFiles.map (·.path)}"
  -- Extra five from probe; not opening const. TON shares the constants/invariants
  -- envelope; Quint/Soroban/ICP/OpenVM require an empty constants table.
  for (target, kind, marker) in #[
      (TargetId.ton, TargetKind.ton, "constants/invariants"),
      (TargetId.quint, TargetKind.quint, "constants"),
      (TargetId.soroban, TargetKind.soroban, "constants"),
      (TargetId.icp, TargetKind.icp, "constants"),
      (TargetId.openvm, TargetKind.openvm, "constants")] do
    expectMaterializePlanInvariantV1 "constant" target kind constCompiled marker

  let invariantSource ← liftResult (← session.selectProgramV1
    invariantTargetBoundarySourceTextV1 "<targets-invariant-boundary>"
      "Tests.Targets.InvariantTargetBoundary" none)
  let invariantCompiled ← liftResult <|
    Compiler.compileValidatedSourceV1 invariantSource
  let invariantData ← match validateSemanticProgramV1
      (CompiledSemanticV1.semanticV1Of invariantCompiled) with
    | .ok data => pure data
    | .error error =>
        throw <| IO.userError s!"invariant boundary: invalid semantic {repr error}"
  expect (invariantData.invariants.size == 1 &&
      invariantData.callables.any (fun callable => callable.kind == .invariant))
    "invariant boundary: Normalize must retain callable and InvariantDecl"
  for (target, kind, marker) in #[
      (TargetId.evm, TargetKind.evm, "constants/invariants"),
      (TargetId.solana, TargetKind.solana,
        "CPI derive rejects nonempty invariants table"),
      -- NEAR admits nonempty invariants only with proof-bearing erasure auth;
      -- ordinary materialize fails closed without that authorization.
      (TargetId.near, TargetKind.near,
        "proof-bearing NEAR invariant-root erasure"),
      -- CosmWasm still FC on invariants (const table is open; invariants are not).
      (TargetId.cosmwasm, TargetKind.cosmwasm, "invariants are outside"),
      (TargetId.noir, TargetKind.noir, "constants/invariants"),
      (TargetId.aleo, TargetKind.aleo, "does not support invariants"),
      (TargetId.psy, TargetKind.psy, "unsupported Psy DPN semantic shape")] do
    expectMaterializePlanInvariantV1 "invariant" target kind invariantCompiled marker
  -- Extra five from probe. Entry is `tick` (not reserved `run`) so Quint Q0
  -- admits the read-only Bool invariant; TON/Soroban/ICP/OpenVM stay FC.
  -- Not opening invariants on those four.
  let quintInv ← liftResult <| materializeSelected TargetId.quint invariantCompiled
  expect (!(MaterializedArtifactsV1.filesOf quintInv).isEmpty)
    "invariant/quint: Q0 read-only Bool invariant must materialize"
  for (target, kind, marker) in #[
      (TargetId.ton, TargetKind.ton, "constants/invariants"),
      (TargetId.soroban, TargetKind.soroban, "invariants"),
      (TargetId.icp, TargetKind.icp, "invariants"),
      (TargetId.openvm, TargetKind.openvm, "invariants")] do
    expectMaterializePlanInvariantV1 "invariant" target kind invariantCompiled marker

/-- N-STR-EVENT opens only the shared Semantic/Reference contract. Every target
    must still reject String event/error ABI materialization rather than silently
    narrowing or omitting the canonical payload. Aleo declines effect.event at
    requirement resolution; the other five reach their target-owned Plan gate. -/
private unsafe def testStringInterfaceMaterializationFailClosed : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let (source, origins) ← match ← session.selectProgramV1WithOrigins
      stringInterfaceBoundarySourceTextV1 "targets/string-interface-boundary.pf"
        "Tests.Targets.StringInterfaceBoundary" none with
    | .ok pair => pure pair
    | .error error =>
        throw <| IO.userError s!"string interface: load failed: {error.render}"
  let compiled ← match Compiler.compileProgramProductV1 source origins with
    | .ok value => pure value
    | .error _ =>
        throw <| IO.userError "string interface: product compile failed"
  let data ← match validateSemanticProgramV1
      (CompiledSemanticV1.semanticV1Of compiled) with
    | .ok value => pure value
    | .error error =>
        throw <| IO.userError s!"string interface: invalid semantic {repr error}"
  let some eventRow := data.events[0]? |
    throw <| IO.userError "string interface: missing EventDecl"
  let some errorRow := data.errors[0]? |
    throw <| IO.userError "string interface: missing ErrorDecl"
  let some eventField := eventRow.fields[0]? |
    throw <| IO.userError "string interface: missing event field"
  let some errorField := errorRow.fields[0]? |
    throw <| IO.userError "string interface: missing error field"
  expect (data.events.size == 1 && data.errors.size == 1 &&
      eventRow.fields.size == 1 && errorRow.fields.size == 1)
    "string interface: Normalize must retain both interface declarations"
  let eventTid := eventField.typeId
  expect (errorField.typeId == eventTid &&
      match data.types[eventTid.toNat]? with
      | some decl => decl.name.isNone &&
          match decl.shape with | .string => true | _ => false
      | none => false)
    "string interface: event/error fields must bind one anonymous String TypeId"
  for (target, kind, marker) in #[
      (TargetId.evm, TargetKind.evm, "fields must be public UInt64"),
      -- Sole rail solana-sbpf-cpi-elf-v1 / Escrow CPI IR fail-closed wording.
      (TargetId.solana, TargetKind.solana, "only UInt64/UInt8"),
      (TargetId.near, TargetKind.near, "only UInt8"),
      (TargetId.noir, TargetKind.noir, "only UInt8"),
      (TargetId.psy, TargetKind.psy, "emit does not accept aggregate arguments")] do
    match materializeSelected target compiled with
    | .error (.planInvariant actualKind message) =>
        expect (actualKind == kind && message.contains marker)
          s!"string interface/{target}: expected marker '{marker}', got {message}"
    | .error error =>
        throw <| IO.userError
          s!"string interface/{target}: expected PF-PLAN-INVARIANT, got {error.render}"
    | .ok _ =>
        throw <| IO.userError
          s!"string interface/{target}: materialization must fail closed"
  match materializeSelected TargetId.aleo compiled with
  | .error (.unsupportedRequirementV1 message) =>
      expect (message.contains "effect.event")
        s!"string interface/aleo: expected effect.event decline, got {message}"
  | .error error =>
      throw <| IO.userError
        s!"string interface/aleo: expected PF-REQ-UNSUPPORTED, got {error.render}"
  | .ok _ =>
      throw <| IO.userError
        "string interface/aleo: materialization must fail closed"
  -- Extra six from probe; not opening String event/error ABI.
  -- CosmWasm/TON reach Plan type-closure; Quint/Soroban/ICP/OpenVM decline
  -- effect.event at requirement resolution (same class as Aleo).
  for (target, kind, marker) in #[
      (TargetId.cosmwasm, TargetKind.cosmwasm, "UInt"),
      (TargetId.ton, TargetKind.ton, "UInt")] do
    expectMaterializePlanInvariantV1 "string interface" target kind compiled marker
  for target in [TargetId.quint, TargetId.soroban, TargetId.icp, TargetId.openvm] do
    match materializeSelected target compiled with
    | .error (.unsupportedRequirementV1 message) =>
        expect (message.contains "effect.event")
          s!"string interface/{target}: expected effect.event decline, got {message}"
    | .error error =>
        throw <| IO.userError
          s!"string interface/{target}: expected PF-REQ-UNSUPPORTED, got {error.render}"
    | .ok _ =>
        throw <| IO.userError
          s!"string interface/{target}: materialization must fail closed"

/-- N-FOR-INT opens target-neutral signed bounded-for semantics only. Until a
    target owns a signed induction/update surface, each of the six target Plan
    builders must reject the retained Int64 loop rather than treating its
    two's-complement values as an unsigned/Felt range. -/
private unsafe def testIntForMaterializationFailClosed : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let (source, origins) ← match ← session.selectProgramV1WithOrigins
      intForBoundarySourceTextV1 "targets/int-for-boundary.pf"
        "Tests.Targets.IntForBoundary" none with
    | .ok pair => pure pair
    | .error error =>
        throw <| IO.userError s!"int for boundary: load failed: {error.render}"
  let compiled ← match Compiler.compileProgramProductV1 source origins with
    | .ok value => pure value
    | .error _ =>
        throw <| IO.userError "int for boundary: product compile failed"
  let data ← match validateSemanticProgramV1
      (CompiledSemanticV1.semanticV1Of compiled) with
    | .ok value => pure value
    | .error error =>
        throw <| IO.userError s!"int for boundary: invalid semantic {repr error}"
  let some callable := data.callables.find? (fun c => c.name == some "iterate") |
    throw <| IO.userError "int for boundary: missing iterate callable"
  let some loopBound := callable.loopBounds[0]? |
    throw <| IO.userError "int for boundary: missing loop bound"
  let some header := callable.blocks[loopBound.header.toNat]? |
    throw <| IO.userError "int for boundary: missing loop header"
  let some induction := header.params[0]? |
    throw <| IO.userError "int for boundary: missing induction parameter"
  expect (callable.loopBounds.size == 1 && header.params.size == 1 &&
      match data.types[induction.typeId.toNat]? with
      | some decl => decl.name.isNone &&
          match decl.shape with | .int 64 => true | _ => false
      | none => false)
    "int for boundary: Normalize must retain one Int64 loop induction"
  for (target, kind, marker) in #[
      (TargetId.evm, TargetKind.evm, "block parameter must be anonymous UInt64"),
      (TargetId.solana, TargetKind.solana, "loop induction parameter must be UInt64"),
      (TargetId.near, TargetKind.near, "loop induction must be public UInt64"),
      (TargetId.noir, TargetKind.noir, "loop header must carry one UInt64 parameter"),
      (TargetId.aleo, TargetKind.aleo, "does not support Int64 for-loop endpoints"),
      (TargetId.psy, TargetKind.psy, "loop header must carry one UInt64 parameter")] do
    expectMaterializePlanInvariantV1 "int-for" target kind compiled marker
  -- Extra six from probe; not opening signed for-loop / Int64 induction.
  -- CosmWasm/TON share the public-UInt64 induction gate. Envelope-4 now
  -- admit Int64 width so they fail on the single-block loopBounds gate.
  for (target, kind, marker) in #[
      (TargetId.cosmwasm, TargetKind.cosmwasm, "loop induction must be public UInt64"),
      (TargetId.ton, TargetKind.ton, "loop induction must be public UInt64"),
      (TargetId.quint, TargetKind.quint, "loopBounds are outside Q0"),
      (TargetId.soroban, TargetKind.soroban, "loopBounds are outside S0"),
      (TargetId.icp, TargetKind.icp, "loopBounds are outside ICP-2"),
      (TargetId.openvm, TargetKind.openvm, "loopBounds are outside O0")] do
    expectMaterializePlanInvariantV1 "int-for" target kind compiled marker

/-- N-ANON-RESULT opens only the shared Semantic/Reference result contract.
    None of the six target-owned ABIs may reinterpret an anonymous Array result
    as a named aggregate or silently omit its canonical container value. -/
private unsafe def testAnonymousResultMaterializationFailClosed : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let (source, origins) ← match ← session.selectProgramV1WithOrigins
      anonymousResultBoundarySourceTextV1 "targets/anonymous-result-boundary.pf"
        "Tests.Targets.AnonymousResultBoundary" none with
    | .ok pair => pure pair
    | .error error =>
        throw <| IO.userError s!"anonymous result boundary: load failed: {error.render}"
  let compiled ← match Compiler.compileProgramProductV1 source origins with
    | .ok value => pure value
    | .error _ =>
        throw <| IO.userError "anonymous result boundary: product compile failed"
  let data ← match validateSemanticProgramV1
      (CompiledSemanticV1.semanticV1Of compiled) with
    | .ok value => pure value
    | .error error =>
        throw <| IO.userError s!"anonymous result boundary: invalid semantic {repr error}"
  let some arrayTid := data.types.findSome? (fun decl =>
      match decl.name, decl.shape with
      | none, .array _ 2 => some decl.id
      | _, _ => none) |
    throw <| IO.userError "anonymous result boundary: missing anonymous Array TypeId"
  let some callable := data.callables.find? (fun c => c.name == some "getArray") |
    throw <| IO.userError "anonymous result boundary: missing getArray"
  expect (callable.result.typeId == arrayTid)
    "anonymous result boundary: Normalize must retain anonymous Array result TypeId"
  -- EVM admits anonymous Array UInt64 N (N≤8) returns (BL-18).
  match materializeSelected TargetId.evm compiled with
  | .ok _ => pure ()
  | .error e =>
      throw <| IO.userError
        s!"anonymous-result: evm must admit Array UInt64 2 return, got {e.render}"
  -- Solana admits anonymous Array UInt64 N (N≤8) returns (BL-19).
  match materializeSelected TargetId.solana compiled with
  | .ok _ => pure ()
  | .error e =>
      throw <| IO.userError
        s!"anonymous-result: solana must admit Array UInt64 2 return, got {e.render}"
  -- NEAR admits anonymous Array UInt64 N (N≤8) returns (BL-20).
  match materializeSelected TargetId.near compiled with
  | .ok _ => pure ()
  | .error e =>
      throw <| IO.userError
        s!"anonymous-result: near must admit Array UInt64 2 return, got {e.render}"
  -- Psy admits anonymous Array UInt64 N (N≤8) returns (BL-25).
  match materializeSelected TargetId.psy compiled with
  | .ok _ => pure ()
  | .error e =>
      throw <| IO.userError
        s!"anonymous-result: psy must admit Array UInt64 2 return, got {e.render}"
  -- Noir admits anonymous Array UInt64 N (N≤8) returns (BL-21).
  match materializeSelected TargetId.noir compiled with
  | .ok _ => pure ()
  | .error e =>
      throw <| IO.userError
        s!"anonymous-result: noir must admit Array UInt64 2 return, got {e.render}"
  -- TON admits anonymous Array UInt64 N (N≤8) view returns (BL-23).
  match materializeSelected TargetId.ton compiled with
  | .ok _ => pure ()
  | .error e =>
      throw <| IO.userError
        s!"anonymous-result: ton must admit Array UInt64 2 view return, got {e.render}"
  -- Aleo: view-over-state anonymous Array return is a query descriptor
  -- (`kind=computed`, result leaf array). Same class as ArrViewRet.
  match materializeSelected TargetId.aleo compiled with
  | .ok out =>
      expect (!(MaterializedArtifactsV1.filesOf out).isEmpty)
        "anonymous-result: aleo must materialize Array UInt64 2 view return"
  | .error e =>
      throw <| IO.userError
        s!"anonymous-result: aleo must admit view-over-state Array return as query descriptor, got {e.render}"
  -- Aleo admits state-touching ENTRY anonymous Array returns via the Final
  -- evaluate-leaves-and-drop path (BL-24).
  let aleoArrEntrySource :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program ArrRetEntry where\n" ++
    "  state slots : Array UInt64 2\n\n" ++
    "  init(x : UInt64, y : UInt64) do\n" ++
    "    slots[0] := x\n" ++
    "    slots[1] := y\n\n" ++
    "  entry getArr() : Array UInt64 2 do\n" ++
    "    return slots\n\n" ++
    "end ProofForgeV2.Examples\n"
  let arrEntryV1 ← match ← session.selectProgramV1 aleoArrEntrySource
      "<targets-anon-result-aleo>" "Examples.ArrRetEntry" none with
    | .ok v => pure v
    | .error e => throw <| IO.userError s!"anon-result aleo-entry select: {e.render}"
  let arrEntryCompiled ← liftResult <| Compiler.compileValidatedSourceV1 arrEntryV1
  match materializeSelected TargetId.aleo arrEntryCompiled with
  | .ok _ => pure ()
  | .error e =>
      throw <| IO.userError
        s!"anonymous-result: aleo must admit entry Array UInt64 2 return, got {e.render}"
  -- CosmWasm admits anonymous Array UInt64 N (N≤8) view returns (BL-22).
  match materializeSelected TargetId.cosmwasm compiled with
  | .ok _ => pure ()
  | .error e =>
      throw <| IO.userError
        s!"anonymous-result: cosmwasm must admit Array UInt64 2 view return, got {e.render}"
  -- Extra four from probe; Aleo query-descriptor pin is above.
  -- Quint/Soroban/ICP/OpenVM stay envelope FC.
  for target in [TargetId.quint, TargetId.soroban, TargetId.icp, TargetId.openvm] do
    match materializeSelected target compiled with
    | .ok _ =>
        throw <| IO.userError
          s!"anonymous-result: {target} must decline Array view-return"
    | .error e =>
        expect ((e.render).contains "Array" ||
            (e.render).contains "aggregate" ||
            (e.render).contains "query" ||
            (e.render).contains "container" ||
            (e.render).contains "unsupported" ||
            (e.render).contains "pilot" ||
            (e.render).contains "anonymous")
          s!"anonymous-result {target} message must cite Array/container boundary, got {e.render}"

private def testSemanticPlanSourceAuthority : IO Unit := do
  -- Extra eight from probe; Soroban facade defers the three tokens to
  -- LowerSemanticV1. Forbidden stays residual-alpha-free. Not a 13th target.
  for target in #["Evm", "Solana", "Near", "Noir", "Aleo", "Psy", "Quint",
      "CosmWasm", "Ton", "Soroban", "OpenVM", "Icp"] do
    let facade := s!"ProofForgeV2/Targets/{target}.lean"
    let lower := s!"ProofForgeV2/Targets/{target}/LowerSemanticV1.lean"
    let forbiddenNeedle :=
      "alphaResidualOf|makePlanFromAlpha|validateRequirementEnvelope|Semantic\\.deriveRequirements"
    let requiredNeedle :=
      "semanticV1Of|validateSemanticProgramV1|makePlanFromSemanticV1"
    let forbiddenFacade ← IO.Process.output {
      cmd := "rg"
      args := #["-n", forbiddenNeedle, facade]
    }
    expect (forbiddenFacade.exitCode == 1)
      s!"{target} facade must not retain a residual-alpha route:\n{forbiddenFacade.stdout}"
    let forbiddenLower ← IO.Process.output {
      cmd := "rg"
      args := #["-n", forbiddenNeedle, lower]
    }
    expect (forbiddenLower.exitCode == 1)
      s!"{target} LowerSemanticV1 must not retain a residual-alpha route:\n{forbiddenLower.stdout}"
    let requiredFacade ← IO.Process.output {
      cmd := "rg"
      args := #["-n", requiredNeedle, facade]
    }
    let facadeHasAll :=
      requiredFacade.exitCode == 0 &&
        requiredFacade.stdout.contains "semanticV1Of" &&
        requiredFacade.stdout.contains "validateSemanticProgramV1" &&
        requiredFacade.stdout.contains "makePlanFromSemanticV1"
    if facadeHasAll then
      pure ()
    else
      let requiredLower ← IO.Process.output {
        cmd := "rg"
        args := #["-n", requiredNeedle, lower]
      }
      expect (requiredLower.exitCode == 0 &&
          requiredLower.stdout.contains "semanticV1Of" &&
          requiredLower.stdout.contains "validateSemanticProgramV1" &&
          requiredLower.stdout.contains "makePlanFromSemanticV1")
        s!"{target} Plan body (facade or LowerSemanticV1) must visibly consume retained SemanticProgramV1:\nfacade={requiredFacade.stdout}\nlower={requiredLower.stdout}"

private unsafe def testRichUInt64SemanticPlans : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source ← liftResult (← session.selectProgramV1
    richUInt64SourceTextV1 "<targets-rich-uint64>" "Tests.Targets.Ledger" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 source
  let evm ← liftResult <| planEvm compiled
  let solana ← liftResult <| planSolana compiled
  let near ← liftResult <| planNear compiled
  let noir ← liftResult <| planNoir compiled

  expect (evm.storageLayout.size == 2 &&
      evm.entries.map (·.name) == #["mix", "getRight"])
    "EVM retained V1 rich S1 layout/callable order"

  expect (solana.stateAccount.fields == #[
      { sourceId := 0, name := "left", accountIndex := 0, byteOffset := 8,
        byteWidth := 8, endianness := .little },
      { sourceId := 1, name := "right", accountIndex := 0, byteOffset := 16,
        byteWidth := 8, endianness := .little }])
    "Solana retained V1 state ids must map to canonical account offsets"
  expect (solana.initializer.params == #[
      { sourceId := 0, name := "a", dataOffset := 8, byteWidth := 8,
        endianness := .little },
      { sourceId := 1, name := "b", dataOffset := 16, byteWidth := 8,
        endianness := .little }] &&
      solana.initializer.body == #[
        .store { accountIndex := 0, byteOffset := 8, value := .param 8 },
        .store { accountIndex := 0, byteOffset := 16, value := .param 16 },
        .returnNone ])
    "Solana initializer must preserve parameter and store order"
  expect (solana.entries.map (·.name) == #["mix", "getRight"] &&
      solana.entries[0]!.params == #[
        { sourceId := 0, name := "x", dataOffset := 8, byteWidth := 8,
          endianness := .little },
        { sourceId := 1, name := "y", dataOffset := 16, byteWidth := 8,
          endianness := .little }] &&
      solana.entries[0]!.body == #[
        .store {
          accountIndex := 0
          byteOffset := 8
          value := .checkedSub (.checkedAdd (.stateLoad 0 8) (.param 8)) (.param 16)
        },
        .store {
          accountIndex := 0
          byteOffset := 16
          value := .checkedSub (.stateLoad 0 16) (.param 8)
        },
        .returnValue (.stateLoad 0 8)] &&
      solana.entries[1]!.body == #[.returnValue (.stateLoad 0 16)])
    "Solana SSA lowering must preserve nested add/sub, store order, and post-store reads"

  expect (near.storage.fields.map (fun field =>
      (field.sourceId, field.name)) == #[(0, "left"), (1, "right")])
    "NEAR retained V1 state ids must preserve declaration order"
  expect (near.initializer.params == #[
      { sourceId := 0, name := "a", inputOffset := 0, byteWidth := 8,
        endianness := .little },
      { sourceId := 1, name := "b", inputOffset := 8, byteWidth := 8,
        endianness := .little }] &&
      near.initializer.body == #[
        .store { fieldIndex := 0, value := .param 0 },
        .store { fieldIndex := 1, value := .param 8 },
        .returnNone ])
    "NEAR initializer must preserve parameter and store order"
  expect (near.entries.map (·.name) == #["mix", "getRight"] &&
      near.entries[0]!.params == #[
        { sourceId := 0, name := "x", inputOffset := 0, byteWidth := 8,
          endianness := .little },
        { sourceId := 1, name := "y", inputOffset := 8, byteWidth := 8,
          endianness := .little }] &&
      near.entries[0]!.body == #[
        .store {
          fieldIndex := 0
          value := .checkedSub (.checkedAdd (.stateLoad 0) (.param 0)) (.param 8)
        },
        .store {
          fieldIndex := 1
          value := .checkedSub (.stateLoad 1) (.param 0)
        },
        .returnValue (.stateLoad 0)] &&
      near.entries[1]!.body == #[.returnValue (.stateLoad 1)])
    "NEAR SSA lowering must preserve nested add/sub, store order, and post-store reads"

  expect (noir.states == #[
      { sourceId := 0, name := "left" },
      { sourceId := 1, name := "right" }] &&
      noir.relations.map (·.name) == #["init", "mix", "getRight"])
    "Noir retained V1 states and relations must preserve source order"
  expect (noir.relations[0]!.params == #[
      { sourceId := 0, name := "a", inputIndex := 1, visibility := .verifier },
      { sourceId := 1, name := "b", inputIndex := 2, visibility := .verifier }] &&
      noir.relations[0]!.body == #[
        .store { fieldIndex := 0, value := .param 1 },
        .store { fieldIndex := 1, value := .param 2 },
        .returnNone])
    "Noir initializer relation must preserve parameter and store order"
  expect (noir.relations[1]!.params == #[
      { sourceId := 0, name := "x", inputIndex := 3, visibility := .verifier },
      { sourceId := 1, name := "y", inputIndex := 4, visibility := .verifier }] &&
      noir.relations[1]!.body == #[
        .store {
          fieldIndex := 0
          value := .checkedSub (.checkedAdd (.stateLoad 0) (.param 3)) (.param 4)
        },
        .store {
          fieldIndex := 1
          value := .checkedSub (.stateLoad 1) (.param 3)
        },
        .returnValue (.stateLoad 0)] &&
      noir.relations[2]!.body == #[.returnValue (.stateLoad 1)])
    "Noir SSA lowering must preserve nested add/sub, store order, and post-store reads"

  -- The private target Plan→IR→emitter chains must retain subtraction and each
  -- target's own underflow failure model; Plan-only assertions are insufficient.
  let solanaIR ← liftResult <| irSolana compiled
  let nearIR ← liftResult <| irNear compiled
  let noirIR ← liftResult <| irNoir compiled
  expect (solanaIR.handlers[1]!.operations.contains
      (.checkedSub 4 2 3 solana.arithmeticOverflowError) &&
      solanaIR.handlers[1]!.operations.contains
        (.checkedSub 2 0 1 solana.arithmeticOverflowError))
    "Solana IR must preserve both checked substitutions and shared error code"
  expect (nearIR.methods[1]!.operations.contains (.checkedSub 4 2 3) &&
      nearIR.methods[1]!.operations.contains (.checkedSub 7 5 6))
    "NEAR recipe IR must preserve both checked substitutions"
  expect (noirIR.relations[1]!.operations.contains
      (.checkedSub 1 (.temp 0) (.input 4)) &&
      noirIR.relations[1]!.operations.contains
        (.checkedSub 2 (.input 2) (.input 3)))
    "Noir relation IR must preserve both checked substitutions"

  let solanaOutput ← liftResult <| materializeSelected TargetId.solana compiled
  let nearOutput ← liftResult <| materializeSelected TargetId.near compiled
  let noirOutput ← liftResult <| materializeSelected TargetId.noir compiled
  let some solanaPlanText := solanaOutput.files.find?
      (·.path == "Ledger.s") |
    throw <| IO.userError "rich add/sub: missing Ledger.s"
  expect ((solanaPlanText.contents.splitOn "checked_sub_u64").length == 3 &&
      solanaPlanText.contents.contains "jlt r1, r2, err_sub_2" &&
      solanaPlanText.contents.contains
        "err_sub_2:\n  lddw r0, 0x1001\n  exit" &&
      solanaPlanText.contents.contains "jlt r1, r2, err_sub_4" &&
      solanaPlanText.contents.contains
        "err_sub_4:\n  lddw r0, 0x1001\n  exit")
    "Solana emitter must retain both checked-sub branches and 0x1001 failure exits"
  let some nearWat := nearOutput.files.find? (·.path == "Ledger.wat") |
    throw <| IO.userError "rich add/sub: missing Ledger.wat"
  expect (nearWat.contents.contains
      "(if (i64.lt_u (local.get $t2) (local.get $t3)) (then unreachable))" &&
      nearWat.contents.contains
        "(local.set $t4 (i64.sub (local.get $t2) (local.get $t3)))")
    "NEAR WAT must trap on unsigned underflow before subtraction"
  let some noirSource := noirOutput.files.find?
      (·.path == "relations/r1-mix/src/main.nr") |
    throw <| IO.userError "rich add/sub: missing Noir mix relation"
  expect (noirSource.contents.contains "assert(t0 >= arg_p1);" &&
      noirSource.contents.contains "let t1: u64 = t0 - arg_p1;")
    "Noir source must constrain underflow before subtraction"
  -- Extra eight from probe; public UInt64 Ledger lighthouse. All twelve
  -- materialize. Not opening a new shape; existing four Plan pins unchanged.
  for target in [TargetId.evm, TargetId.solana, TargetId.near, TargetId.noir,
      TargetId.aleo, TargetId.psy, TargetId.quint, TargetId.cosmwasm,
      TargetId.ton, TargetId.soroban, TargetId.openvm, TargetId.icp] do
    let out ← liftResult <| materializeSelected target compiled
    expect (!(MaterializedArtifactsV1.filesOf out).isEmpty)
      s!"rich UInt64 Ledger: {target} must materialize"

private def boolPredicateSourceTextV1 : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n" ++
  "program BoolPredicate where\n" ++
  "  state count : UInt64\n" ++
  "  init(initial : UInt64) do\n" ++
  "    count := initial\n" ++
  "  entry bump(delta : UInt64) : UInt64 do\n" ++
  "    count := count + delta\n" ++
  "    return count\n" ++
  "  view positive() : Bool do\n" ++
  "    return count > 0\n" ++
  "  entry equalsCount(delta : UInt64) : Bool do\n" ++
  "    return count == delta\n"

/-- Four-target retained-V1 Bool-result conformance: mixed UInt64/Bool
    entry/view results keep exact per-target result kinds and ABI surfaces. -/
private unsafe def testBoolPredicateSemanticPlans : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source ← liftResult (← session.selectProgramV1
    boolPredicateSourceTextV1 "<targets-bool-predicate>" "Tests.Targets.BoolPredicate" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 source
  let evm ← liftResult <| planEvm compiled
  let solana ← liftResult <| planSolana compiled
  let near ← liftResult <| planNear compiled
  let noir ← liftResult <| planNoir compiled

  expect (evm.entries.map (·.name) == #["bump", "positive", "equalsCount"] &&
      evm.entries.map (·.resultKind) == #[.uint64, .bool, .bool])
    "EVM result kinds must stay uint64/bool/bool in source order"
  expect (evm.entries[1]!.body == #[
      .returnValue (.compare .gt (.storageLoad 0) (.literal 0))] &&
      evm.entries[2]!.body == #[
        .returnValue (.compare .eq (.storageLoad 0) (.param 0))])
    "EVM Bool entries must return the comparison expressions"

  expect (solana.entries.map (·.name) == #["bump", "positive", "equalsCount"] &&
      solana.entries.map (·.resultKind) == #[.u64, .bool, .bool])
    "Solana result kinds must stay u64/bool/bool in source order"
  expect (solana.entries[1]!.body == #[
      .returnValue (.compare .gt (.stateLoad 0 8) (.literal 0))] &&
      solana.entries[2]!.body == #[
        .returnValue (.compare .eq (.stateLoad 0 8) (.param 8))])
    "Solana Bool handlers must return the comparison expressions"

  expect (near.entries.map (·.name) == #["bump", "positive", "equalsCount"] &&
      near.entries.map (·.resultKind) == #[.uint64, .bool, .bool])
    "NEAR result kinds must stay uint64/bool/bool in source order"

  expect (noir.relations.map (·.name) == #["init", "bump", "positive", "equalsCount"])
    "Noir relations must preserve source order"
  let noirPositive := noir.relations[2]!
  let noirPosResult := noirPositive.inputs.filter (·.role == .result)
  expect (noirPosResult.size == 1 && noirPosResult[0]!.type == .bool)
    "Noir positive relation must bind a Bool result input"
  let noirBumpResult := noir.relations[1]!.inputs.filter (·.role == .result)
  expect (noirBumpResult.size == 1 && noirBumpResult[0]!.type != .bool)
    "Noir bump relation must keep a UInt64 result input"

  let solanaIR ← liftResult <| irSolana compiled
  expect (solanaIR.handlers[2]!.operations.contains (.setReturnDataBool 2) &&
      !(solanaIR.handlers[0]!.operations.any (fun
        | .setReturnDataBool _ => true | _ => false)))
    "Solana IR must route Bool handlers to setReturnDataBool and UInt64 to setReturnData"
  let nearIR ← liftResult <| irNear compiled
  expect (nearIR.methods.map (·.name) == #["init", "bump", "positive", "equalsCount"])
    "NEAR recipe IR must preserve method order for mixed result kinds"

  let solanaOutput ← liftResult <| materializeSelected TargetId.solana compiled
  let nearOutput ← liftResult <| materializeSelected TargetId.near compiled
  let noirOutput ← liftResult <| materializeSelected TargetId.noir compiled
  let some solanaIdl := solanaOutput.files.find?
      (·.path == "BoolPredicate.idl.json") |
    throw <| IO.userError "bool-predicate: missing Solana IDL"
  expect (solanaIdl.contents.contains
      "\"schema\":\"proof-forge.solana.cpi-idl.v1\"" &&
      solanaIdl.contents.contains "\"name\":\"bump\"" &&
      solanaIdl.contents.contains "\"name\":\"positive\"" &&
      solanaIdl.contents.contains "\"name\":\"equalsCount\"")
    "Solana CPI IDL must preserve all instruction identities"
  let some solanaAsm := solanaOutput.files.find?
      (·.path == "BoolPredicate.s") |
    throw <| IO.userError "bool-predicate: missing Solana assembly"
  expect ((solanaAsm.contents.splitOn "set_return_data_u64_le").length == 2 &&
      (solanaAsm.contents.splitOn "set_return_data_bool").length == 3)
    "Solana assembly must carry one UInt64 and two Bool return-data paths"
  let some noirSource := noirOutput.files.find?
      (·.path == "relations/r2-positive/src/main.nr") |
    throw <| IO.userError "bool-predicate: missing Noir positive relation"
  expect (noirSource.contents.contains "result: pub bool" &&
      noirSource.contents.contains "assert(result ==")
    "Noir source must declare pub bool result bound by assert"
  let some nearAbi := nearOutput.files.find?
      (fun f => f.path.endsWith ".near-abi.json") |
    throw <| IO.userError "bool-predicate: missing NEAR ABI"
  expect (nearAbi.contents.contains "\"bool\"")
    "NEAR ABI must carry the bool result type"
  -- Extra eight + EVM from probe; Bool view/entry lighthouse. Twelve
  -- materialize (ICP Bool results + Aleo computed query view).
  -- Existing four Plan/IR/IDL pins unchanged.
  for target in [TargetId.evm, TargetId.solana, TargetId.near, TargetId.noir,
      TargetId.psy, TargetId.quint, TargetId.cosmwasm, TargetId.ton,
      TargetId.soroban, TargetId.openvm, TargetId.icp, TargetId.aleo] do
    let out ← liftResult <| materializeSelected target compiled
    expect (!(MaterializedArtifactsV1.filesOf out).isEmpty)
      s!"BoolPredicate: {target} must materialize"

/-- ProgramV1 branching source text for the Wave C if/match multi-block leaf. -/
private def branchFlowSourceTextV1 : String :=
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

/-- Four-target retained-V1 if/match multi-block conformance: branch diamond
    plus literal-match switch lowered through Plan, typed IR regions, and
    each target's emitter surface. -/
private unsafe def testBranchingSemanticPlans : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source ← liftResult (← session.selectProgramV1
    branchFlowSourceTextV1 "<targets-branching>" "Tests.Targets.BranchFlow" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 source
  let evm ← liftResult <| planEvm compiled
  let solana ← liftResult <| planSolana compiled
  let near ← liftResult <| planNear compiled
  let noir ← liftResult <| planNoir compiled

  expect (evm.entries.map (·.name) == #["bump", "apply", "get"])
    "EVM branching entries must preserve source order"
  expect (evm.entries[0]!.body == #[
      .ifThenElse (.compare .gt (.storageLoad 0) (.literal 0))
        #[.store { slot := 0, value := .checkedAdd (.storageLoad 0) (.param 0) }]
        #[.store { slot := 0, value := .param 0 }],
      .returnValue (.storageLoad 0)])
    "EVM bump must lower the if/else diamond then the join return"
  expect (evm.entries[1]!.body == #[
      .switchOn (.param 0)
        #[(0, #[.returnValue (.storageLoad 0)]),
          (1, #[.store { slot := 0, value := .checkedAdd (.storageLoad 0) (.literal 1) }])]
        #[.store { slot := 0, value := .param 0 }],
      .returnValue (.storageLoad 0)])
    "EVM apply must lower the literal match to a switch with a bind default"

  expect (solana.entries[0]!.body == #[
      .ifThenElse (.compare .gt (.stateLoad 0 8) (.literal 0))
        #[.store {
          accountIndex := 0
          byteOffset := 8
          value := .checkedAdd (.stateLoad 0 8) (.param 8)
        }]
        #[.store { accountIndex := 0, byteOffset := 8, value := .param 8 }],
      .returnValue (.stateLoad 0 8)])
    "Solana bump must lower the if/else diamond then the join return"
  expect (solana.entries[1]!.body == #[
      .switchOn (.param 8)
        #[(0, #[.returnValue (.stateLoad 0 8)]),
          (1, #[.store {
            accountIndex := 0
            byteOffset := 8
            value := .checkedAdd (.stateLoad 0 8) (.literal 1)
          }])]
        #[.store { accountIndex := 0, byteOffset := 8, value := .param 8 }],
      .returnValue (.stateLoad 0 8)])
    "Solana apply must lower the literal match to a switch with a bind default"

  expect (near.entries[0]!.body == #[
      .ifThenElse (.compare .gt (.stateLoad 0) (.literal 0))
        #[.store { fieldIndex := 0, value := .checkedAdd (.stateLoad 0) (.param 0) }]
        #[.store { fieldIndex := 0, value := .param 0 }],
      .returnValue (.stateLoad 0)])
    "NEAR bump must lower the if/else diamond then the join return"
  expect (near.entries[1]!.body == #[
      .switchOn (.param 0)
        #[(0, #[.returnValue (.stateLoad 0)]),
          (1, #[.store {
            fieldIndex := 0
            value := .checkedAdd (.stateLoad 0) (.literal 1)
          }])]
        #[.store { fieldIndex := 0, value := .param 0 }],
      .returnValue (.stateLoad 0)])
    "NEAR apply must lower the literal match to a switch with a bind default"

  expect (noir.relations.map (·.name) == #["init", "bump", "apply", "get"])
    "Noir branching relations must preserve source order"
  let noirIR ← liftResult <| irNoir compiled
  let noirBump := noirIR.relations[1]!
  expect (noirBump.operations.any (fun
      | .ifRegion .. => true | _ => false))
    "Noir bump relation must lower the diamond to an ifRegion of complete paths"
  let noirApply := noirIR.relations[2]!
  expect (noirApply.operations.any (fun
      | .switchRegion .. => true | _ => false))
    "Noir apply relation must lower the match to a switchRegion"
  liftResult <| Targets.Noir.validateIR noirIR

  let solanaIR ← liftResult <| irSolana compiled
  expect (solanaIR.handlers[1]!.operations.any (fun
      | .ifRegion .. => true | _ => false) &&
      solanaIR.handlers[2]!.operations.any (fun
      | .switchRegion .. => true | _ => false))
    "Solana IR must carry if/switch regions on the branching handlers"
  let nearIR ← liftResult <| irNear compiled
  expect (nearIR.methods[1]!.operations.any (fun
      | .ifRegion .. => true | _ => false) &&
      nearIR.methods[2]!.operations.any (fun
      | .switchRegion .. => true | _ => false))
    "NEAR recipe IR must carry if/switch regions on the branching methods"

  let evmOutput ← liftResult <| materializeSelected TargetId.evm compiled
  let solanaOutput ← liftResult <| materializeSelected TargetId.solana compiled
  let nearOutput ← liftResult <| materializeSelected TargetId.near compiled
  let noirOutput ← liftResult <| materializeSelected TargetId.noir compiled
  let some yulFile := evmOutput.files.find? (·.path == "BranchFlow.yul") |
    throw <| IO.userError "branching: missing BranchFlow.yul"
  expect (yulFile.contents.contains "if expr" &&
      yulFile.contents.contains "if eq(expr")
    "branching Yul must render branch and switch guards"
  let some sbpf := solanaOutput.files.find? (·.path == "BranchFlow.s") |
    throw <| IO.userError "branching: missing BranchFlow.s"
  expect (sbpf.contents.contains "; if %2" &&
      sbpf.contents.contains "if_else_" && sbpf.contents.contains "if_end_" &&
      sbpf.contents.contains "; switch %0" &&
      (sbpf.contents.splitOn "jeq r1, r2, sw_case_").length == 3 &&
      sbpf.contents.contains "sw_end_")
    "branching s must render the if diamond, two literal cases, and default fallthrough"
  let some wat := nearOutput.files.find? (·.path == "BranchFlow.wat") |
    throw <| IO.userError "branching: missing BranchFlow.wat"
  expect (wat.contents.contains "(if (i64.ne (local.get $t")
    "branching WAT must render i64 region conditions as Wasm i32 predicates"
  let some bumpNr := noirOutput.files.find?
      (·.path == "relations/r1-bump/src/main.nr") |
    throw <| IO.userError "branching: missing Noir bump relation"
  expect (bumpNr.contents.contains "if t" && bumpNr.contents.contains "} else {")
    "branching Noir source must render the if/else region"
  let some applyNr := noirOutput.files.find?
      (·.path == "relations/r2-apply/src/main.nr") |
    throw <| IO.userError "branching: missing Noir apply relation"
  expect (applyNr.contents.contains "else if" &&
      applyNr.contents.contains "== 0")
    "branching Noir source must render the switch as an else-if chain"
  -- Extra eight from probe; BranchFlow if/match lighthouse. Aleo/Psy/CW/TON
  -- admit. Quint/Soroban/OpenVM/ICP stay on the single-block envelope.
  -- Not opening multi-block CFG; existing four Plan/IR/file pins unchanged.
  for target in [TargetId.evm, TargetId.solana, TargetId.near, TargetId.noir,
      TargetId.aleo, TargetId.psy, TargetId.cosmwasm, TargetId.ton] do
    let out ← liftResult <| materializeSelected target compiled
    expect (!(MaterializedArtifactsV1.filesOf out).isEmpty)
      s!"BranchFlow: {target} must materialize"
  for (target, kind) in #[
      (TargetId.quint, TargetKind.quint),
      (TargetId.soroban, TargetKind.soroban),
      (TargetId.openvm, TargetKind.openvm),
      (TargetId.icp, TargetKind.icp)] do
    expectMaterializePlanInvariantV1 "BranchFlow" target kind compiled
      "exactly one block"

/-- ProgramV1 fn/localCall source text for the Wave E pureCall leaf. -/
private def fnFlowSourceTextV1 : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n" ++
  "program FnFlow where\n" ++
  "  state count : UInt64\n" ++
  "  error Cap(limit : UInt64)\n" ++
  "  fn double(x : UInt64) : UInt64 do\n" ++
  "    return x + x\n" ++
  "  fn check(x : UInt64, lim : UInt64) : UInt64 do\n" ++
  "    if x > lim then\n" ++
  "      revert Cap(lim)\n" ++
  "    else\n" ++
  "      return double(x)\n" ++
  "  init(initial : UInt64) do\n" ++
  "    count := initial\n" ++
  "  entry bump(delta : UInt64) : UInt64 do\n" ++
  "    count := check(delta, 10) + double(count)\n" ++
  "    return count\n" ++
  "  view get() : UInt64 do\n" ++
  "    return count\n"

/-- Four-target retained-V1 pureCall conformance: dense fn tables, nested
    localCall lowering with exact args, typed IR call operations, and each
    target's emitter surface for pure functions (Yul functions, SBPF inline
    call/return markers, WAT funcs, Noir block-valued selects). -/
private unsafe def testFnLocalCallSemanticPlans : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source ← liftResult (← session.selectProgramV1
    fnFlowSourceTextV1 "<targets-fn-call>" "Tests.Targets.FnFlow" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 source
  let evm ← liftResult <| planEvm compiled
  let solana ← liftResult <| planSolana compiled
  let near ← liftResult <| planNear compiled
  let noir ← liftResult <| planNoir compiled

  expect (evm.fns.map (·.name) == #["double", "check"] &&
      solana.fns.map (·.name) == #["double", "check"] &&
      near.fns.map (·.name) == #["double", "check"] &&
      noir.fns.map (·.name) == #["double", "check"])
    "all four targets must carry the double/check fn tables in source order"
  expect (evm.fns[1]!.body == #[
      .ifThenElse (.compare .gt (.param 0) (.param 1))
        #[.revertError 0 #[.param 1]]
        #[.returnValue (.callFn 0 #[.param 0])]])
    "EVM check body must lower the revert arm and the nested double call"
  expect (evm.entries[0]!.body == #[
      .store { slot := 0, value :=
        .checkedAdd (.callFn 1 #[.param 0, .literal 10]) (.callFn 0 #[.storageLoad 0]) },
      .returnValue (.storageLoad 0)])
    "EVM bump must add check(delta,10) and double(count)"
  expect (solana.entries[0]!.body == #[
      .store { accountIndex := 0, byteOffset := 8, value :=
        .checkedAdd (.callFn 1 #[.param 8, .literal 10]) (.callFn 0 #[.stateLoad 0 8]) },
      .returnValue (.stateLoad 0 8)])
    "Solana bump must add check(delta,10) and double(count)"
  expect (near.entries[0]!.body == #[
      .store { fieldIndex := 0, value :=
        .checkedAdd (.callFn 1 #[.param 0, .literal 10]) (.callFn 0 #[.stateLoad 0]) },
      .returnValue (.stateLoad 0)])
    "NEAR bump must add check(delta,10) and double(count)"
  let forgedUnboundNearFn := {
    near.fns[0]! with body := #[.returnValue (.localTemp 0)]
  }
  match Targets.Near.validatePlan {
      near with fns := near.fns.set! 0 forgedUnboundNearFn
    } with
  | .error (.planInvariant .near _) => pure ()
  | _ =>
      throw <| IO.userError
        "NEAR Plan validation must reject an unbound pureFn localTemp"
  expect (noir.relations.map (·.name) == #["init", "bump", "get"])
    "Noir relations must stay init/entry/view only (fns inline, no fn relations)"
  let noirBump := noir.relations[1]!
  let noirIR ← liftResult <| irNoir compiled
  liftResult <| Targets.Noir.validateIR noirIR
  let noirBumpIR := noirIR.relations[1]!
  expect (noirBumpIR.operations.any (fun
      | .selectRegion .. => true | _ => false))
    "Noir bump must inline check as a block-valued select"

  let solanaIR ← liftResult <| irSolana compiled
  expect (solanaIR.fns.size == 2 &&
      solanaIR.handlers[1]!.operations.any (fun
      | .callFn .. => true | _ => false))
    "Solana IR must carry fn bodies and callFn ops"
  let nearIR ← liftResult <| irNear compiled
  expect (nearIR.fns.size == 2 &&
      nearIR.methods[1]!.operations.any (fun
      | .callFn .. => true | _ => false))
    "NEAR recipe IR must carry fn bodies and callFn ops"
  match Targets.Near.validateWATModuleFnReferencesV1 nearIR with
  | .ok () => pure ()
  | .error error =>
      throw <| IO.userError
        s!"production NEAR pureFn references must validate: {error.render}"
  let wrongNearFnSignature := {
    nearIR.fns[0]! with paramCount := nearIR.fns[0]!.paramCount + 1
  }
  match Targets.Near.validateWATModuleFnReferencesV1
      (Targets.Near.withFns nearIR (nearIR.fns.set! 0 wrongNearFnSignature)) with
  | .error (.planInvariant .near _) => pure ()
  | _ =>
      throw <| IO.userError
        "NEAR WAT module validation must reject a forged pureFn signature"
  let danglingNestedNearCall := {
    nearIR.methods[1]! with
    operations := #[.ifRegion 0 #[.callFn nearIR.fns.size 0 #[]] #[]]
  }
  let danglingNestedNearIR :=
    Targets.Near.withMethods nearIR
      (nearIR.methods.set! 1 danglingNestedNearCall)
  match Targets.Near.validateWATModuleFnReferencesV1
      danglingNestedNearIR with
  | .error (.planInvariant .near _) => pure ()
  | _ =>
      throw <| IO.userError
        "NEAR WAT module validation must reject a nested dangling pureFn call"
  match Targets.Near.validateIR danglingNestedNearIR with
  | .error (.planInvariant .near _) => pure ()
  | _ =>
      throw <| IO.userError
        "production NEAR IR validation must reject a nested dangling pureFn call"
  let wrongArityNearCall := {
    nearIR.methods[1]! with operations := #[.callFn 0 0 #[]]
  }
  match Targets.Near.validateWATModuleFnReferencesV1
      (Targets.Near.withMethods nearIR
        (nearIR.methods.set! 1 wrongArityNearCall)) with
  | .error (.planInvariant .near _) => pure ()
  | _ =>
      throw <| IO.userError
        "NEAR WAT module validation must reject a wrong-arity pureFn call"

  let evmOutput ← liftResult <| materializeSelected TargetId.evm compiled
  let solanaOutput ← liftResult <| materializeSelected TargetId.solana compiled
  let nearOutput ← liftResult <| materializeSelected TargetId.near compiled
  let noirOutput ← liftResult <| materializeSelected TargetId.noir compiled
  let some yulFile := evmOutput.files.find? (·.path == "FnFlow.yul") |
    throw <| IO.userError "fn-call: missing FnFlow.yul"
  expect (yulFile.contents.contains "function pf_fn0(" &&
      yulFile.contents.contains "function pf_fn1(" &&
      yulFile.contents.contains "pf_fn1(" && yulFile.contents.contains "pf_fn0(")
    "fn-call Yul must define and call both pure functions"
  let some sbpf := solanaOutput.files.find? (·.path == "FnFlow.s") |
    throw <| IO.userError "fn-call: missing FnFlow.s"
  expect ((sbpf.contents.splitOn "; call check →").length == 2 &&
      (sbpf.contents.splitOn "; call double →").length == 3 &&
      (sbpf.contents.splitOn "; fn ret u64").length == 4 &&
      sbpf.contents.contains "lddw r0, 0x2000\n  exit")
    "fn-call s must inline check/double calls, returns, and the declared-error exit"
  let some wat := nearOutput.files.find? (·.path == "FnFlow.wat") |
    throw <| IO.userError "fn-call: missing FnFlow.wat"
  expect (wat.contents.contains "(func $fn_double" &&
      wat.contents.contains "(func $fn_check" &&
      wat.contents.contains "(call $fn_check" &&
      wat.contents.contains "(call $fn_double")
    "fn-call WAT must render fn definitions and call sites"
  let some bumpNr := noirOutput.files.find?
      (·.path == "relations/r1-bump/src/main.nr") |
    throw <| IO.userError "fn-call: missing Noir bump relation"
  expect (bumpNr.contents.contains ": u64 = if" &&
      bumpNr.contents.contains "assert(false)")
    "fn-call Noir source must inline check as a block-valued select with an inadmissible revert arm"
  -- Extra eight from probe; FnFlow localCall + typed Cap revert lighthouse.
  -- CW/TON admit. Aleo/Psy typed payload, Quint/Soroban/OpenVM zero-payload
  -- errors, ICP empty-errors stay named FC. Not opening localCall/typed-revert;
  -- existing four Plan/IR pins unchanged.
  for target in [TargetId.evm, TargetId.solana, TargetId.near, TargetId.noir,
      TargetId.cosmwasm, TargetId.ton] do
    let out ← liftResult <| materializeSelected target compiled
    expect (!(MaterializedArtifactsV1.filesOf out).isEmpty)
      s!"FnFlow: {target} must materialize"
  expectMaterializePlanInvariantV1 "FnFlow" TargetId.aleo TargetKind.aleo
    compiled "does not support revert payloads"
  expectMaterializePlanInvariantV1 "FnFlow" TargetId.psy TargetKind.psy
    compiled "structured DPN error ABI"
  expectMaterializePlanInvariantV1 "FnFlow" TargetId.quint TargetKind.quint
    compiled "declared errors must have zero payload fields"
  expectMaterializePlanInvariantV1 "FnFlow" TargetId.soroban TargetKind.soroban
    compiled "declared errors must have zero payload fields"
  expectMaterializePlanInvariantV1 "FnFlow" TargetId.openvm TargetKind.openvm
    compiled "declared errors must have zero payload fields"
  expectMaterializePlanInvariantV1 "FnFlow" TargetId.icp TargetKind.icp
    compiled "errors table must be empty"

/-- ProgramV1 emit/revert source text for the Wave D event/error leaf. -/
private def eventFlowSourceTextV1 : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n" ++
  "program EventFlow where\n" ++
  "  state count : UInt64\n" ++
  "  event Moved(src : UInt64, dst : UInt64)\n" ++
  "  error Cap(limit : UInt64)\n" ++
  "  init(initial : UInt64) do\n" ++
  "    count := initial\n" ++
  "  entry bump(delta : UInt64) : UInt64 do\n" ++
  "    emit Moved(count, delta)\n" ++
  "    if count > delta then\n" ++
  "      revert Cap(delta)\n" ++
  "    else\n" ++
  "      count := count + delta\n" ++
  "    return count\n" ++
  "  view get() : UInt64 do\n" ++
  "    return count\n"

/-- Four-target retained-V1 emit/revert conformance: declared event/error
    tables, emit-then-branch-revert Plan shapes, typed IR operations, and
    each target's emitter surface for events and declared reverts. -/
private unsafe def testEmitRevertSemanticPlans : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source ← liftResult (← session.selectProgramV1
    eventFlowSourceTextV1 "<targets-emit-revert>" "Tests.Targets.EventFlow" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 source
  let evm ← liftResult <| planEvm compiled
  let solana ← liftResult <| planSolana compiled
  let near ← liftResult <| planNear compiled
  let noir ← liftResult <| planNoir compiled

  expect (evm.events.map (·.name) == #["Moved"] &&
      evm.errors.map (·.name) == #["Cap"] &&
      solana.events.map (·.name) == #["Moved"] &&
      solana.errors.map (·.name) == #["Cap"] &&
      near.events.map (·.name) == #["Moved"] &&
      near.errors.map (·.name) == #["Cap"] &&
      noir.events.map (·.name) == #["Moved"] &&
      noir.errors.map (·.name) == #["Cap"])
    "all four targets must carry the declared Moved/Cap bindings"
  expect (evm.entries[0]!.body == #[
      .emitEvent 0 #[.storageLoad 0, .param 0],
      .ifThenElse (.compare .gt (.storageLoad 0) (.param 0))
        #[.revertError 0 #[.param 0]]
        #[.store { slot := 0, value := .checkedAdd (.storageLoad 0) (.param 0) }],
      .returnValue (.storageLoad 0)])
    "EVM bump must lower emit, branch revert, join return"
  expect (solana.entries[0]!.body == #[
      .emitEvent 0 #[.stateLoad 0 8, .param 8],
      .ifThenElse (.compare .gt (.stateLoad 0 8) (.param 8))
        #[.revertError 0 #[.param 8]]
        #[.store {
          accountIndex := 0
          byteOffset := 8
          value := .checkedAdd (.stateLoad 0 8) (.param 8)
        }],
      .returnValue (.stateLoad 0 8)])
    "Solana bump must lower emit, branch revert, join return"
  expect (near.entries[0]!.body == #[
      .emitEvent 0 #[.stateLoad 0, .param 0],
      .ifThenElse (.compare .gt (.stateLoad 0) (.param 0))
        #[.revertError 0 #[.param 0]]
        #[.store {
          fieldIndex := 0
          value := .checkedAdd (.stateLoad 0) (.param 0)
        }],
      .returnValue (.stateLoad 0)])
    "NEAR bump must lower emit, branch revert, join return"
  expect (noir.relations.map (·.name) == #["init", "bump", "get"])
    "Noir relations must preserve source order"
  let noirBump := noir.relations[1]!
  let slotInputs := noirBump.inputs.filter fun binding =>
    match binding.role with | .eventSlot .. => true | _ => false
  expect (slotInputs.map (·.name) == #["ev_e0_a0", "ev_e0_a1"] &&
      slotInputs.all (·.visibility == .verifier))
    "Noir bump must bind the two canonical verifier event slots"
  let noirIR ← liftResult <| irNoir compiled
  liftResult <| Targets.Noir.validateIR noirIR

  let solanaIR ← liftResult <| irSolana compiled
  expect (solanaIR.handlers[1]!.operations.any (fun
      | .emitEvent .. => true | _ => false) &&
      solanaIR.handlers[1]!.operations.any (fun
      | .ifRegion .. => true | _ => false))
    "Solana IR must carry the emit op and the revert region"
  let nearIR ← liftResult <| irNear compiled
  expect (nearIR.methods[1]!.operations.any (fun
      | .emitEvent .. => true | _ => false) &&
      nearIR.methods[1]!.operations.any (fun
      | .ifRegion .. => true | _ => false))
    "NEAR recipe IR must carry the emit op and the revert region"

  let evmOutput ← liftResult <| materializeSelected TargetId.evm compiled
  let solanaOutput ← liftResult <| materializeSelected TargetId.solana compiled
  let nearOutput ← liftResult <| materializeSelected TargetId.near compiled
  let noirOutput ← liftResult <| materializeSelected TargetId.noir compiled
  let expectedTopic := Targets.Evm.Keccak.keccak256Hex "Moved(uint64,uint64)".toUTF8
  let some yulFile := evmOutput.files.find? (·.path == "EventFlow.yul") |
    throw <| IO.userError "emit-revert: missing EventFlow.yul"
  expect (yulFile.contents.contains s!"log1(0, 64, 0x{expectedTopic})" &&
      yulFile.contents.contains "revert(0, 36)")
    "emit-revert Yul must render log1 with the Moved topic and the Cap revert"
  let some abiFile := evmOutput.files.find? (·.path == "EventFlow.abi.json") |
    throw <| IO.userError "emit-revert: missing EventFlow.abi.json"
  expect (abiFile.contents.contains "\"type\":\"event\",\"name\":\"Moved\"" &&
      abiFile.contents.contains "\"type\":\"error\",\"name\":\"Cap\"")
    "emit-revert ABI must declare the Moved event and Cap error"
  let some sbpf := solanaOutput.files.find? (·.path == "EventFlow.s") |
    throw <| IO.userError "emit-revert: missing EventFlow.s"
  expect (sbpf.contents.contains
      "; emit_event Moved (index 0, 2 args) via sol_log_data" &&
      sbpf.contents.contains "call sol_log_data" &&
      sbpf.contents.contains "; program_error declared index 0" &&
      sbpf.contents.contains "lddw r0, 0x2000\n  exit")
    "emit-revert s must log Moved and return the declared Cap error code"
  let some wat := nearOutput.files.find? (·.path == "EventFlow.wat") |
    throw <| IO.userError "emit-revert: missing EventFlow.wat"
  expect (wat.contents.contains "pf_log_utf8" &&
      wat.contents.contains "pf_panic_utf8")
    "emit-revert WAT must render the log/panic host calls"
  let some bumpNr := noirOutput.files.find?
      (·.path == "relations/r1-bump/src/main.nr") |
    throw <| IO.userError "emit-revert: missing Noir bump relation"
  expect (bumpNr.contents.contains "ev_e0_a0: pub u64" &&
      bumpNr.contents.contains "assert(false)")
    "emit-revert Noir source must declare event slots and the inadmissible revert path"
  -- Extra eight from probe; EventFlow emit/revert lighthouse. CosmWasm/TON
  -- admit. Aleo/Quint/Soroban/OpenVM/ICP decline effect.event at requirement
  -- resolve. Psy declines typed Cap payload (zero-payload named revert stays
  -- open). Not opening events; existing four Plan/IR pins unchanged.
  for target in [TargetId.evm, TargetId.solana, TargetId.near, TargetId.noir,
      TargetId.cosmwasm, TargetId.ton] do
    let out ← liftResult <| materializeSelected target compiled
    expect (!(MaterializedArtifactsV1.filesOf out).isEmpty)
      s!"EventFlow: {target} must materialize"
  for target in [TargetId.aleo, TargetId.quint, TargetId.soroban,
      TargetId.openvm, TargetId.icp] do
    match materializeSelected target compiled with
    | .error (.unsupportedRequirementV1 message) =>
        expect (message.contains "effect.event")
          s!"EventFlow/{target}: expected effect.event decline, got {message}"
    | .error error =>
        throw <| IO.userError
          s!"EventFlow/{target}: expected PF-REQ-UNSUPPORTED, got {error.render}"
    | .ok _ =>
        throw <| IO.userError
          s!"EventFlow/{target}: materialization must fail closed"
  expectMaterializePlanInvariantV1 "EventFlow" TargetId.psy TargetKind.psy
    compiled "structured DPN error ABI"

/-- ProgramV1 guarded-stateCell source text for the comparison+assert leaf. -/
private def guardedStateCellSourceTextV1 : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n" ++
  "program Guarded where\n" ++
  "  state count : UInt64\n" ++
  "  init(initial : UInt64) do\n" ++
  "    count := initial\n" ++
  "  entry decrement(delta : UInt64) : UInt64 do\n" ++
  "    assert count >= delta\n" ++
  "    count := count - delta\n" ++
  "    return count\n" ++
  "  view get() : UInt64 do\n" ++
  "    return count\n"

/-- Four-target retained-V1 comparison+assert Plan/IR/emitter conformance for
    the guarded stateCell: assert(ge) → checkedSub → return, with each target's
    own assert failure rendering. -/
private unsafe def testGuardedStateCellSemanticPlans : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source ← liftResult (← session.selectProgramV1
    guardedStateCellSourceTextV1 "<targets-guarded>" "Tests.Targets.Guarded" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 source
  let evm ← liftResult <| planEvm compiled
  let solana ← liftResult <| planSolana compiled
  let near ← liftResult <| planNear compiled
  let noir ← liftResult <| planNoir compiled

  expect (evm.entries.map (·.name) == #["decrement", "get"] &&
      evm.entries[0]!.body == #[
        .assert (.compare .ge (.storageLoad 0) (.param 0)),
        .store { slot := 0, value := .checkedSub (.storageLoad 0) (.param 0) },
        .returnValue (.storageLoad 0)])
    "EVM retained V1 must lower assert(ge) → checkedSub store → return in order"

  expect (solana.entries.map (·.name) == #["decrement", "get"] &&
      solana.entries[0]!.body == #[
        .assert (.compare .ge (.stateLoad 0 8) (.param 8)),
        .store {
          accountIndex := 0
          byteOffset := 8
          value := .checkedSub (.stateLoad 0 8) (.param 8)
        },
        .returnValue (.stateLoad 0 8)])
    "Solana retained V1 must lower assert(ge) → checkedSub store → return in order"

  expect (near.entries.map (·.name) == #["decrement", "get"] &&
      near.entries[0]!.body == #[
        .assert (.compare .ge (.stateLoad 0) (.param 0)),
        .store {
          fieldIndex := 0
          value := .checkedSub (.stateLoad 0) (.param 0)
        },
        .returnValue (.stateLoad 0)])
    "NEAR retained V1 must lower assert(ge) → checkedSub store → return in order"

  expect (noir.relations.map (·.name) == #["init", "decrement", "get"] &&
      noir.relations[1]!.body == #[
        .assert (.compare .ge (.stateLoad 0) (.param 2)),
        .store {
          fieldIndex := 0
          value := .checkedSub (.stateLoad 0) (.param 2)
        },
        .returnValue (.stateLoad 0)])
    "Noir retained V1 must lower assert(ge) → checkedSub store → return in order"

  let solanaIR ← liftResult <| irSolana compiled
  let nearIR ← liftResult <| irNear compiled
  let noirIR ← liftResult <| irNoir compiled
  expect (solanaIR.handlers[1]!.operations.contains
      (.compare 2 0 1 .ge) &&
      solanaIR.handlers[1]!.operations.contains
        (.assert 2 solana.assertionFailedError))
    "Solana IR must keep the ge compare immediately feeding the assert"
  expect (nearIR.methods[1]!.operations.contains (.compare 2 0 1 .ge) &&
      nearIR.methods[1]!.operations.contains (.assert 2))
    "NEAR recipe IR must keep the ge compare immediately feeding the assert"
  let noirOps := noirIR.relations[1]!.operations
  expect (noirOps.any (fun | .compare .ge .. => true | _ => false) &&
      noirOps.any (fun | .assertConstraint _ => true | _ => false))
    "Noir relation IR must keep a ge compare with an assertConstraint"

  let solanaOutput ← liftResult <| materializeSelected TargetId.solana compiled
  let nearOutput ← liftResult <| materializeSelected TargetId.near compiled
  let noirOutput ← liftResult <| materializeSelected TargetId.noir compiled
  let some solanaPlanText := solanaOutput.files.find?
      (·.path == "Guarded.s") |
    throw <| IO.userError "guarded: missing Guarded.s"
  expect (solanaPlanText.contents.contains "jge r1, r2, cmp_true_0" &&
      solanaPlanText.contents.contains "; assert %2" &&
      solanaPlanText.contents.contains "jeq r1, 0, err_assert_2" &&
      solanaPlanText.contents.contains
        "err_assert_2:\n  lddw r0, 0x1002\n  exit")
    "Solana emitter must retain the ge branch and 0x1002 assert failure exit"
  let some nearWat := nearOutput.files.find? (·.path == "Guarded.wat") |
    throw <| IO.userError "guarded: missing Guarded.wat"
  expect (nearWat.contents.contains "i64.ge_u" &&
      nearWat.contents.contains "(then unreachable)")
    "NEAR WAT must emit the unsigned ge comparison and assert trap"
  let some noirSource := noirOutput.files.find?
      (·.path == "relations/r1-decrement/src/main.nr") |
    throw <| IO.userError "guarded: missing Noir decrement relation"
  expect (noirSource.contents.contains ">=" && noirSource.contents.contains "assert(")
    "Noir source must constrain the ge comparison and assert"
  -- Extra eight + EVM from probe; Guarded assert+checkedSub lighthouse.
  -- Eleven materialize. ICP still has no assert op (Counter/StateCell
  -- envelope). Not opening assert; existing four Plan pins unchanged.
  for target in [TargetId.evm, TargetId.solana, TargetId.near, TargetId.noir,
      TargetId.aleo, TargetId.psy, TargetId.quint, TargetId.cosmwasm,
      TargetId.ton, TargetId.soroban, TargetId.openvm] do
    let out ← liftResult <| materializeSelected target compiled
    expect (!(MaterializedArtifactsV1.filesOf out).isEmpty)
      s!"Guarded: {target} must materialize"
  expectMaterializePlanInvariantV1 "Guarded" TargetId.icp TargetKind.icp
    compiled "op is outside the ICP-2"

/-- ProgramV1 ArithFlow source text for the Wave F arithmetic/unary leaf. -/
private def arithFlowSourceTextV1 : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n" ++
  "program ArithFlow where\n" ++
  "  state count : UInt64\n" ++
  "  init(initial : UInt64) do\n" ++
  "    count := initial\n" ++
  "  entry scale(factor : UInt64) : UInt64 do\n" ++
  "    count := count * factor / 3 + count % 3\n" ++
  "    return count\n" ++
  "  entry mask(value : UInt64) : UInt64 do\n" ++
  "    count := ~value\n" ++
  "    return count\n" ++
  "  view parity() : Bool do\n" ++
  "    return !(count % 2 == 0)\n"

/-- Four-target retained-V1 arithmetic conformance: mul/div/mod and unary
    bitNot/boolNot Plan trees, typed IR operations, and each target's
    emitter surface for the new operators. -/
private unsafe def testArithOpsSemanticPlans : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source ← liftResult (← session.selectProgramV1
    arithFlowSourceTextV1 "<targets-arith-ops>" "Tests.Targets.ArithFlow" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 source
  let evm ← liftResult <| planEvm compiled
  let solana ← liftResult <| planSolana compiled
  let near ← liftResult <| planNear compiled
  let noir ← liftResult <| planNoir compiled

  expect (evm.entries.map (·.name) == #["scale", "mask", "parity"] &&
      solana.entries.map (·.name) == #["scale", "mask", "parity"] &&
      near.entries.map (·.name) == #["scale", "mask", "parity"])
    "all three account-model targets must carry scale/mask/parity in source order"
  expect (noir.relations.map (·.name) == #["init", "scale", "mask", "parity"])
    "Noir relations must be init/scale/mask/parity in source order"

  expect (evm.entries[0]!.body == #[
      .store { slot := 0, value :=
        .checkedAdd (.checkedDiv (.checkedMul (.storageLoad 0) (.param 0)) (.literal 3)) (.checkedMod (.storageLoad 0) (.literal 3)) },
      .returnValue (.storageLoad 0)])
    "EVM scale must lower count * factor / 3 + count % 3 left-assoc into checked ops"
  expect (evm.entries[1]!.body == #[
      .store { slot := 0, value := .bitNot (.param 0) },
      .returnValue (.storageLoad 0)])
    "EVM mask must lower ~value into bitNot"
  expect (evm.entries[2]!.resultKind == .bool &&
      evm.entries[2]!.body == #[
        .returnValue (.boolNot
          (.compare .eq (.checkedMod (.storageLoad 0) (.literal 2)) (.literal 0)))])
    "EVM parity must return boolNot over a mod-by-2 equality"

  expect (solana.entries[0]!.body == #[
      .store { accountIndex := 0, byteOffset := 8, value :=
        .checkedAdd (.checkedDiv (.checkedMul (.stateLoad 0 8) (.param 8)) (.literal 3)) (.checkedMod (.stateLoad 0 8) (.literal 3)) },
      .returnValue (.stateLoad 0 8)])
    "Solana scale must lower count * factor / 3 + count % 3 into checked ops"
  expect (solana.entries[1]!.body == #[
      .store { accountIndex := 0, byteOffset := 8, value := .bitNot (.param 8) },
      .returnValue (.stateLoad 0 8)])
    "Solana mask must lower ~value into bitNot"

  expect (near.entries[0]!.body == #[
      .store { fieldIndex := 0, value :=
        .checkedAdd (.checkedDiv (.checkedMul (.stateLoad 0) (.param 0)) (.literal 3)) (.checkedMod (.stateLoad 0) (.literal 3)) },
      .returnValue (.stateLoad 0)])
    "NEAR scale must lower count * factor / 3 + count % 3 into checked ops"
  expect (near.entries[1]!.body == #[
      .store { fieldIndex := 0, value := .bitNot (.param 0) },
      .returnValue (.stateLoad 0)])
    "NEAR mask must lower ~value into bitNot"

  let noirIR ← liftResult <| irNoir compiled
  liftResult <| Targets.Noir.validateIR noirIR
  let noirScaleOps := noirIR.relations[1]!.operations
  let arithOnly := noirScaleOps.filter fun op =>
    match op with
    | .checkedMul .. | .checkedDiv .. | .checkedMod .. | .checkedAdd .. => true
    | _ => false
  expect (arithOnly.size == 4)
    "Noir scale must emit exactly four checked arithmetic ops"
  match arithOnly[0]!, arithOnly[1]!, arithOnly[2]!, arithOnly[3]! with
  | .checkedMul .., .checkedDiv .., .checkedMod .., .checkedAdd .. => pure ()
  | _, _, _, _ =>
      throw <| IO.userError "Noir scale op order must be mul/div/mod/add"
  expect (noirIR.relations[2]!.operations.any (fun
      | .bitNot .. => true | _ => false))
    "Noir mask must emit a bitNot op"
  let noirParityOps := noirIR.relations[3]!.operations
  expect (noirParityOps.any (fun | .checkedMod .. => true | _ => false) &&
      noirParityOps.any (fun | .compare .eq .. => true | _ => false) &&
      noirParityOps.any (fun | .boolNot .. => true | _ => false))
    "Noir parity must emit mod, eq compare, and boolNot"

  let evmOutput ← liftResult <| materializeSelected TargetId.evm compiled
  let solanaOutput ← liftResult <| materializeSelected TargetId.solana compiled
  let nearOutput ← liftResult <| materializeSelected TargetId.near compiled
  let noirOutput ← liftResult <| materializeSelected TargetId.noir compiled
  let some yulFile := evmOutput.files.find? (·.path == "ArithFlow.yul") |
    throw <| IO.userError "arith-ops: missing ArithFlow.yul"
  expect (yulFile.contents.contains "mul(" && yulFile.contents.contains "div(" &&
      yulFile.contents.contains "mod(" && yulFile.contents.contains "not(" &&
      yulFile.contents.contains "and(not(" && yulFile.contents.contains "iszero(")
    "arith-ops Yul must render mul/div/mod/masked-not/iszero"
  let some sbpf := solanaOutput.files.find? (·.path == "ArithFlow.s") |
    throw <| IO.userError "arith-ops: missing ArithFlow.s"
  expect (sbpf.contents.contains "checked_mul_u64" &&
      sbpf.contents.contains "checked_div_u64" &&
      sbpf.contents.contains "checked_rem_u64" &&
      sbpf.contents.contains "checked_add_u64" &&
      sbpf.contents.contains "bitnot_u64" &&
      sbpf.contents.contains "bool_not" &&
      sbpf.contents.contains "lddw r0, 0x1001\n  exit")
    "arith-ops s must render checked mul/div/rem/add and both unary ops"
  let some wat := nearOutput.files.find? (·.path == "ArithFlow.wat") |
    throw <| IO.userError "arith-ops: missing ArithFlow.wat"
  expect (wat.contents.contains "i64.mul" && wat.contents.contains "i64.div_u" &&
      wat.contents.contains "i64.rem_u" && wat.contents.contains "i64.xor" &&
      wat.contents.contains "i64.eqz")
    "arith-ops WAT must render i64 mul/div_u/rem_u/xor/eqz"
  let some scaleNr := noirOutput.files.find?
      (·.path == "relations/r1-scale/src/main.nr") |
    throw <| IO.userError "arith-ops: missing Noir scale relation"
  expect (scaleNr.contents.contains " * " && scaleNr.contents.contains " / " &&
      scaleNr.contents.contains " % " && scaleNr.contents.contains " != 0")
    "arith-ops Noir scale must render mul/div/mod with a divisor guard"
  let some maskNr := noirOutput.files.find?
      (·.path == "relations/r2-mask/src/main.nr") |
    throw <| IO.userError "arith-ops: missing Noir mask relation"
  expect (maskNr.contents.contains ": u64 = !")
    "arith-ops Noir mask must render bitwise NOT on u64"
  let some parityNr := noirOutput.files.find?
      (·.path == "relations/r3-parity/src/main.nr") |
    throw <| IO.userError "arith-ops: missing Noir parity relation"
  expect (parityNr.contents.contains ": bool = !")
    "arith-ops Noir parity must render Bool NOT"
  -- Extra eight from probe; ArithFlow mul/div/mod/bitNot/boolNot lighthouse.
  -- Psy/CW/TON/Aleo admit (Aleo computed Bool view is a query descriptor).
  -- Quint/Soroban/OpenVM/ICP admit mul/div/mod and fail on unary bitNot
  -- (`~value` in mask). existing four Plan/IR pins unchanged.
  for target in [TargetId.evm, TargetId.solana, TargetId.near, TargetId.noir,
      TargetId.psy, TargetId.cosmwasm, TargetId.ton, TargetId.aleo] do
    let out ← liftResult <| materializeSelected target compiled
    expect (!(MaterializedArtifactsV1.filesOf out).isEmpty)
      s!"ArithFlow: {target} must materialize"
  expectMaterializePlanInvariantV1 "ArithFlow" TargetId.quint TargetKind.quint
    compiled "unary neg/bitNot are outside Q0"
  expectMaterializePlanInvariantV1 "ArithFlow" TargetId.soroban TargetKind.soroban
    compiled "unary neg/bitNot are outside S0"
  expectMaterializePlanInvariantV1 "ArithFlow" TargetId.openvm TargetKind.openvm
    compiled "unary neg/bitNot are outside O0"
  expectMaterializePlanInvariantV1 "ArithFlow" TargetId.icp TargetKind.icp
    compiled "op is outside the ICP-2"

/-- Deepest nested if-region depth in a Noir relation operation list (the
    bounded-loop unrolling shape pin). -/
private partial def countIfRegionDepthTargets
    (ops : Array Targets.Noir.Operation) : Nat :=
  ops.foldl (fun acc op =>
    match op with
    | .ifRegion _ thenOps elseOps =>
        max acc (max (1 + countIfRegionDepthTargets thenOps)
          (countIfRegionDepthTargets elseOps))
    | _ => acc) 0

/-- ProgramV1 LoopSum source text for the Wave G let/for leaf. -/
private def loopSumSourceTextV1 : String :=
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

/-- Four-target retained-V1 bounded-loop conformance: the same let+for
    program lowers through all four capability Plans into forLoop
    statements (induction temp, init/cond/update, static bound, body store)
    with exact back-edge bound enforcement on each emitter surface. -/
private unsafe def testForLoopSemanticPlans : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source ← liftResult (← session.selectProgramV1
    loopSumSourceTextV1 "<targets-for-loop>" "Tests.Targets.LoopSum" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 source
  let evm ← liftResult <| planEvm compiled
  let solana ← liftResult <| planSolana compiled
  let near ← liftResult <| planNear compiled
  let noir ← liftResult <| planNoir compiled

  expect (evm.entries.map (·.name) == #["addUp", "scan", "addUpTight", "get"] &&
      solana.entries.map (·.name) == #["addUp", "scan", "addUpTight", "get"] &&
      near.entries.map (·.name) == #["addUp", "scan", "addUpTight", "get"])
    "all three account-model targets must carry addUp/scan/addUpTight/get in source order"
  expect (noir.relations.map (·.name) ==
      #["init", "addUp", "scan", "addUpTight", "get"])
    "Noir relations must be init/addUp/scan/addUpTight/get in source order"

  expect (evm.entries[0]!.body == #[
      .forLoop 1 2 8
        (.param 0)
        (.compare .lt (.temp 1) (.checkedAdd (.param 0) (.literal 4)))
        (.add (.temp 1) (.literal 1))
        #[.store { slot := 0, value := .checkedAdd (.storageLoad 0) (.temp 1) }],
      .returnValue (.storageLoad 0)])
    "EVM addUp must lower let+for into forLoop with stateCell/maxIterations/init/cond/update/body"
  expect (solana.entries[0]!.body == #[
      .forLoop 1
        (.param 8)
        (.compare .lt (.temp 1) (.checkedAdd (.param 8) (.literal 4)))
        (.checkedAdd (.temp 1) (.literal 1))
        8
        #[.store { accountIndex := 0, byteOffset := 8, value := .checkedAdd (.stateLoad 0 8) (.temp 1) }],
      .returnValue (.stateLoad 0 8)])
    "Solana addUp must lower let+for into forLoop with init/cond/update/max/body"
  expect (near.entries[0]!.body == #[
      .forLoop 0
        (.param 0)
        (.compare .lt (.localTemp 0) (.checkedAdd (.param 0) (.literal 4)))
        (.checkedAdd (.localTemp 0) (.literal 1))
        8
        #[.store { fieldIndex := 0, value := .checkedAdd (.stateLoad 0) (.localTemp 0) }],
      .returnValue (.stateLoad 0)])
    "NEAR addUp must lower let+for into forLoop with init/cond/update/max/body"
  expect (noir.relations[1]!.body == #[
      .forLoop 0 8
        (.param 2)
        (.compare .lt (.loopParam 0) (.checkedAdd (.param 2) (.literal 4)))
        (.checkedAdd (.loopParam 0) (.literal 1))
        #[.store { fieldIndex := 0, value := .checkedAdd (.stateLoad 0) (.loopParam 0) }],
      .returnValue (.stateLoad 0)])
    "Noir addUp must lower let+for into forLoop with slot/bound/init/cond/update/body"

  liftResult <| Targets.Evm.validatePlan evm
  liftResult <| Targets.Solana.validatePlan solana
  liftResult <| Targets.Near.validatePlan near
  let noirIR ← liftResult <| irNoir compiled
  liftResult <| Targets.Noir.validateIR noirIR
  expect (countIfRegionDepthTargets noirIR.relations[1]!.operations == 9)
    "Noir addUp must unroll bound 8 into nine nested predicated regions"

  let evmOutput ← liftResult <| materializeSelected TargetId.evm compiled
  let solanaOutput ← liftResult <| materializeSelected TargetId.solana compiled
  let nearOutput ← liftResult <| materializeSelected TargetId.near compiled
  let noirOutput ← liftResult <| materializeSelected TargetId.noir compiled
  let some yulFile := evmOutput.files.find? (·.path == "LoopSum.yul") |
    throw <| IO.userError "for-loop: missing LoopSum.yul"
  expect (yulFile.contents.contains "for {" &&
      yulFile.contents.contains "if eq(t2, 8)" &&
      yulFile.contents.contains "revert(0, 0)")
    "for-loop Yul must render native for loops with the back-edge bound revert"
  let some sbpf := solanaOutput.files.find? (·.path == "LoopSum.s") |
    throw <| IO.userError "for-loop: missing LoopSum.s"
  expect (sbpf.contents.contains "; for max=8" &&
      sbpf.contents.contains "; for max=2" &&
      sbpf.contents.contains "; for max=3" &&
      (sbpf.contents.splitOn "lddw r0, 0x1003\n  exit").length == 4)
    "for-loop s must render all three static bounds with 0x1003 failure exits"
  let some wat := nearOutput.files.find? (·.path == "LoopSum.wat") |
    throw <| IO.userError "for-loop: missing LoopSum.wat"
  expect (wat.contents.contains "(loop $pf_loop" && wat.contents.contains "br_if" &&
      wat.contents.contains "unreachable")
    "for-loop WAT must render block/loop/br_if with the bound trap"
  let some addUpNr := noirOutput.files.find?
      (·.path == "relations/r1-addUp/src/main.nr") |
    throw <| IO.userError "for-loop: missing Noir addUp relation"
  expect (addUpNr.contents.contains "if " && addUpNr.contents.contains "assert(false)")
    "for-loop Noir source must render unrolled predicated ifs with the bound guard"
  -- Extra eight from probe; LoopSum bounded-for lighthouse. Psy/Aleo/CW/TON
  -- admit. Quint/Soroban/OpenVM/ICP stay on the single-block envelope.
  -- Not opening multi-block/for; existing four Plan/IR pins unchanged.
  for target in [TargetId.evm, TargetId.solana, TargetId.near, TargetId.noir,
      TargetId.psy, TargetId.aleo, TargetId.cosmwasm, TargetId.ton] do
    let out ← liftResult <| materializeSelected target compiled
    expect (!(MaterializedArtifactsV1.filesOf out).isEmpty)
      s!"LoopSum: {target} must materialize"
  for (target, kind) in #[
      (TargetId.quint, TargetKind.quint),
      (TargetId.soroban, TargetKind.soroban),
      (TargetId.openvm, TargetKind.openvm),
      (TargetId.icp, TargetKind.icp)] do
    expectMaterializePlanInvariantV1 "LoopSum" target kind compiled
      "exactly one block"

/-- ProgramV1 BitLogic source text for the Wave H shift/bitwise/logical leaf. -/
private def bitLogicSourceTextV1 : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n" ++
  "program BitLogic where\n" ++
  "  state count : UInt64\n" ++
  "  init(initial : UInt64) do\n" ++
  "    count := initial\n" ++
  "  entry shiftMask(x : UInt64) : UInt64 do\n" ++
  "    count := (x << 2) & 15 | (x >> 1) ^ 3\n" ++
  "    return count\n" ++
  "  entry bigShift(x : UInt64) : UInt64 do\n" ++
  "    return x >> (32 + 32)\n" ++
  "  entry both(a : UInt64, b : UInt64) : Bool do\n" ++
  "    return a > 0 && b > 0\n" ++
  "  entry strictOr(a : UInt64, b : UInt64) : Bool do\n" ++
  "    let one : UInt64 := 1\n" ++
  "    return a > 0 || (one / b) == one\n" ++
  "  view get() : UInt64 do\n" ++
  "    return count\n"

/-- Four-target retained-V1 shift/bitwise/logical conformance: the same
    BitLogic program lowers through all four capability Plans with exact
    shift/bitwise trees, strict logical forms, and each emitter's guarded
    shift and policy surfaces. -/
private unsafe def testShiftBitwiseLogicalSemanticPlans : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source ← liftResult (← session.selectProgramV1
    bitLogicSourceTextV1 "<targets-shift-bit>" "Tests.Targets.BitLogic" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 source
  let evm ← liftResult <| planEvm compiled
  let solana ← liftResult <| planSolana compiled
  let near ← liftResult <| planNear compiled
  let noir ← liftResult <| planNoir compiled

  expect (evm.entries.map (·.name) == #["shiftMask", "bigShift", "both", "strictOr", "get"] &&
      solana.entries.map (·.name) == #["shiftMask", "bigShift", "both", "strictOr", "get"] &&
      near.entries.map (·.name) == #["shiftMask", "bigShift", "both", "strictOr", "get"])
    "all three account-model targets must carry the five callables in source order"
  expect (noir.relations.map (·.name) ==
      #["init", "shiftMask", "bigShift", "both", "strictOr", "get"])
    "Noir relations must be init/shiftMask/bigShift/both/strictOr/get in source order"

  expect (evm.entries[0]!.body == #[
      .store {
        slot := 0
        value := .bitOr
          (.bitAnd
            (.shl (.param 0) (.literal 2))
            (.literal 15))
          (.bitXor
            (.shr (.param 0) (.literal 1))
            (.literal 3))
      },
      .returnValue (.storageLoad 0)])
    "EVM shiftMask must lower (x << 2) & 15 | (x >> 1) ^ 3 into the exact tree"
  expect (evm.entries[3]!.body == #[
      .returnValue (.logicalOr (.compare .gt (.param 0) (.literal 0))
        (.compare .eq (.checkedDiv (.literal 1) (.param 1)) (.literal 1)))])
    "EVM strictOr must evaluate both sides (gt/div/eq under logicalOr)"
  expect (solana.entries[0]!.body == #[
      .store {
        accountIndex := 0
        byteOffset := 8
        value := .bitOr
          (.bitAnd
            (.shl (.param 8) (.literal 2))
            (.literal 15))
          (.bitXor
            (.shr (.param 8) (.literal 1))
            (.literal 3))
      },
      .returnValue (.stateLoad 0 8)])
    "Solana shiftMask must lower (x << 2) & 15 | (x >> 1) ^ 3 into the exact tree"
  expect (near.entries[0]!.body == #[
      .store {
        fieldIndex := 0
        value := .bitOr
          (.bitAnd
            (.shl (.param 0) (.literal 2))
            (.literal 15))
          (.bitXor
            (.shr (.param 0) (.literal 1))
            (.literal 3))
      },
      .returnValue (.stateLoad 0)])
    "NEAR shiftMask must lower (x << 2) & 15 | (x >> 1) ^ 3 into the exact tree"
  expect (noir.relations[1]!.body == #[
      .store {
        fieldIndex := 0
        value := .bitOr
          (.bitAnd
            (.shl (.param 2) (.literal 2))
            (.literal 15))
          (.bitXor
            (.shr (.param 2) (.literal 1))
            (.literal 3))
      },
      .returnValue (.stateLoad 0)])
    "Noir shiftMask must lower (x << 2) & 15 | (x >> 1) ^ 3 into the exact tree"
  -- Computed counts reach the shift everywhere (entrypoint is runtime-live).
  match evm.entries[1]!.body[0]? with
  | some (stmt : Targets.Evm.Statement) =>
      match stmt with
      | .returnValue (.shr _ (.checkedAdd ..)) => pure ()
      | .returnValue (.shr _ (.narrowCheckedAdd 32 ..)) => pure ()
      | _ => throw <| IO.userError "EVM bigShift must keep a computed count"
  | none => throw <| IO.userError "EVM bigShift body is empty"
  match near.entries[1]!.body[0]? with
  | some (stmt : Targets.Near.Statement) =>
      match stmt with
      | .returnValue (.shr _ (.checkedAdd ..)) => pure ()
      | .returnValue (.shr _ (.narrowCheckedAdd 32 ..)) => pure ()
      | _ => throw <| IO.userError "NEAR bigShift must keep a computed count"
  | none => throw <| IO.userError "NEAR bigShift body is empty"

  liftResult <| Targets.Evm.validatePlan evm
  liftResult <| Targets.Solana.validatePlan solana
  liftResult <| Targets.Near.validatePlan near
  let noirIR ← liftResult <| irNoir compiled
  liftResult <| Targets.Noir.validateIR noirIR
  let maskOps := noirIR.relations[1]!.operations
  expect (maskOps.any fun op => match op with
      | .checkedMul _ _ (.literal 4) => true | _ => false &&
    maskOps.any fun op => match op with
      | .checkedDiv _ _ (.literal 2) => true | _ => false)
    "Noir shiftMask must lower shifts to multiply/divide by 2^k"

  let evmOutput ← liftResult <| materializeSelected TargetId.evm compiled
  let solanaOutput ← liftResult <| materializeSelected TargetId.solana compiled
  let nearOutput ← liftResult <| materializeSelected TargetId.near compiled
  let noirOutput ← liftResult <| materializeSelected TargetId.noir compiled
  let some yulFile := evmOutput.files.find? (·.path == "BitLogic.yul") |
    throw <| IO.userError "shift-bit: missing BitLogic.yul"
  expect (yulFile.contents.contains "shl(" && yulFile.contents.contains "shr(" &&
      yulFile.contents.contains "and(" && yulFile.contents.contains "xor(" &&
      yulFile.contents.contains "or(" && yulFile.contents.contains "revert(0, 0)")
    "shift-bit Yul must render shl/shr/and/xor/or with revert guards"
  let some sbpf := solanaOutput.files.find? (·.path == "BitLogic.s") |
    throw <| IO.userError "shift-bit: missing BitLogic.s"
  expect (sbpf.contents.contains "bitand_u64" && sbpf.contents.contains "bitor_u64" &&
      sbpf.contents.contains "bitxor_u64" && sbpf.contents.contains "shl_u64" &&
      sbpf.contents.contains "shr_u64" && sbpf.contents.contains "bool_and" &&
      sbpf.contents.contains "bool_or" && sbpf.contents.contains "0x1004")
    "shift-bit s must render the five op families with the entrypoint code"
  let some wat := nearOutput.files.find? (·.path == "BitLogic.wat") |
    throw <| IO.userError "shift-bit: missing BitLogic.wat"
  expect (wat.contents.contains "i64.shl" && wat.contents.contains "i64.shr_u" &&
      wat.contents.contains "i64.and" && wat.contents.contains "i64.xor" &&
      wat.contents.contains "i64.or" && wat.contents.contains "unreachable")
    "shift-bit WAT must render i64 ops with trap guards"
  let some maskNr := noirOutput.files.find?
      (·.path == "relations/r1-shiftMask/src/main.nr") |
    throw <| IO.userError "shift-bit: missing Noir shiftMask relation"
  expect (maskNr.contents.contains " * 4;" && maskNr.contents.contains " / 2;" &&
      maskNr.contents.contains " & " && maskNr.contents.contains " | " &&
      maskNr.contents.contains " ^ ")
    "shift-bit Noir source must render multiply/divide by 2^k and native bitwise ops"
  -- Extra eight from probe; BitLogic shift/bitwise/logical lighthouse.
  -- Psy/CW/TON admit. Aleo Final-only unused-state entry. Envelope-4 now
  -- admit UInt64/Int64/Bool so they fail on bitwise/shift (ICP add/sub+cmp).
  -- Not opening shift/bitwise; existing four Plan/IR/file pins unchanged.
  for target in [TargetId.evm, TargetId.solana, TargetId.near, TargetId.noir,
      TargetId.psy, TargetId.cosmwasm, TargetId.ton] do
    let out ← liftResult <| materializeSelected target compiled
    expect (!(MaterializedArtifactsV1.filesOf out).isEmpty)
      s!"BitLogic: {target} must materialize"
  expectMaterializePlanInvariantV1 "BitLogic" TargetId.aleo TargetKind.aleo
    compiled "function 'bigShift' does not touch state"
  expectMaterializePlanInvariantV1 "BitLogic" TargetId.quint TargetKind.quint
    compiled "bitwise/shift ops are outside Q0"
  expectMaterializePlanInvariantV1 "BitLogic" TargetId.soroban TargetKind.soroban
    compiled "bitwise/shift ops are outside S0"
  expectMaterializePlanInvariantV1 "BitLogic" TargetId.openvm TargetKind.openvm
    compiled "bitwise/shift ops are outside O0"
  expectMaterializePlanInvariantV1 "BitLogic" TargetId.icp TargetKind.icp
    compiled "only checked add/sub/mul/div/mod and comparisons"

/-- Noir constant folding must not evaluate 2^k for huge folded counts: a
    count expression like `0xFFFFFFFF - 1` folds to k ≥ 64 and lowers to the
    literal-false entrypoint guard with a dead wrapped literal. Previously
    the emitter eagerly computed `2 ^ k` as a Nat (~512 MiB allocation / long
    stall) before the guard branch; the wrapped result is byte-identical for
    every k ≥ 64 (2^k mod 2^64 = 0), so the fold must stay cheap. -/
private unsafe def testNoirHugeFoldedShiftCount : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let sourceText :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program HugeCount where\n" ++
    "  entry big(a : UInt64) : UInt64 do\n" ++
    "    return a >> (0xFFFFFFFF - 1)\n"
  let source ← liftResult (← session.selectProgramV1
    sourceText "<targets-huge-count>" "Tests.Targets.HugeCount" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 source
  let noir ← liftResult <| planNoir compiled
  expect (noir.relations.map (·.name) == #["big"])
    "Noir huge-count relations must carry the single entry"
  let ir ← liftResult <| irNoir compiled
  let some bigRelation := ir.relations.find? (fun r => r.sourceRelation.name == "big") |
    throw <| IO.userError "huge-count: missing big relation"
  let bigOps := bigRelation.operations
  expect (bigOps.any fun op => match op with
      | .assertConstraint (.literal 0) => true | _ => false)
    "Noir huge count must render the literal-false entrypoint guard"
  expect (bigOps.any fun op => match op with
      | .checkedDiv _ _ (.literal 0) => true | _ => false)
    "Noir huge count must render a dead wrapped 2^k literal (0)"
  liftResult <| Targets.Noir.validateIR ir

/-- ProgramV1 ExtFlow/LaterFlow source text for the Wave I call/schedule leaf. -/
private def extFlowSourceTextV1 : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n" ++
  "program ExtFlow where\n" ++
  "  state count : UInt64\n" ++
  "  event Ping(x : UInt64)\n" ++
  "  init(initial : UInt64) do\n" ++
  "    count := initial\n" ++
  "  entry bump(delta : UInt64) : UInt64 do\n" ++
  "    emit Ping(count)\n" ++
  "    call Oracle.feed(count)\n" ++
  "    count := count + delta\n" ++
  "    return count\n" ++
  "  entry later(delta : UInt64) : UInt64 do\n" ++
  "    schedule ledger.daily(count)\n" ++
  "    schedule ledger.weekly(delta)\n" ++
  "    return count\n" ++
  "  view get() : UInt64 do\n" ++
  "    return count\n"

private def laterFlowSourceTextV1 : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n" ++
  "program LaterFlow where\n" ++
  "  state count : UInt64\n" ++
  "  init(initial : UInt64) do\n" ++
  "    count := initial\n" ++
  "  entry later(delta : UInt64) : UInt64 do\n" ++
  "    schedule ledger.daily(count)\n" ++
  "    return count\n" ++
  "  view get() : UInt64 do\n" ++
  "    return count\n"

/-- Capability matrix honesty: legacy Solana profiles still decline sync call and
    async workflow. Exact CPI profile (#125) admits sync but still declines async
    (Escrow product positive is covered by SolanaCpiActivationV1). EVM/Noir/Psy
    keep current sync behavior; EVM/NEAR/Noir keep current async behavior.
    ADR-0029 C1/C2: NEAR and CosmWasm advertise the sync-call key for the
    pf.assets catalog scope only; generic non-catalog sync calls resolve but
    stay fail closed at their Plan/lowering layers. -/
private unsafe def testCallScheduleSemanticPlans : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source ← liftResult (← session.selectProgramV1
    extFlowSourceTextV1 "<targets-ext-flow>" "Tests.Targets.ExtFlow" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 source
  -- ExtFlow contains a generic (non-catalog) sync call: after ADR-0029 C2 the
  -- NEAR resolver advertises effect.synchronous-call for the pf.assets catalog
  -- scope, so resolution succeeds, and the generic QN stays fail closed at
  -- Plan (NEAR has no synchronous cross-contract calls).
  let nearSel ← liftResult <| resolveBuildSelectionV1 TargetId.near none
  let nearCapability ← liftResult <|
    Targets.resolveEngineeringRequirementsV1 nearSel compiled
  match Targets.Near.planFromCapability nearCapability with
  | .error e =>
      expect (e.code == "PF-PLAN-INVARIANT")
        s!"near must reject generic sync call at Plan, got {e.render}"
  | .ok _ =>
      throw <| IO.userError "near unexpectedly Plans a generic sync call"
  -- EVM static QN call → Plan.externalCall + CALL Yul.
  let evmSelection ← liftResult <| resolveBuildSelectionV1 TargetId.evm none
  let evmCapability ← liftResult <|
    Targets.resolveEngineeringRequirementsV1 evmSelection compiled
  let evmPlan ← liftResult <| Targets.Evm.planFromCapability evmCapability
  match evmPlan.entries[0]!.body[1]? with
  | some (stmt : Targets.Evm.Statement) =>
      match stmt with
      | .externalCall #["Oracle", "feed"] #[.storageLoad 0] => pure ()
      | _ => throw <| IO.userError "EVM bump must keep externalCall Oracle.feed"
  | none => throw <| IO.userError "EVM bump body is too short"
  let evmOutput ← liftResult <| materializeSelected TargetId.evm compiled
  let some yul := evmOutput.files.find? (·.path == "ExtFlow.yul") |
    throw <| IO.userError "call-schedule: missing ExtFlow.yul"
  expect (yul.contents.contains "call(gas(), 0x")
    "EVM Yul must render CALL to the static keccak-derived address"
  -- Legacy Solana profiles must decline external-effect keys before Plan mint.
  -- ExtFlow requests both call families; canonical requirement wire order
  -- reports asynchronous-workflow first. Call-only exact rejection is pinned
  -- in SolanaPlanV1 for both legacy profiles.
  let solSelection ← liftResult <| resolveBuildSelectionV1 TargetId.solana none
  match Targets.resolveEngineeringRequirementsV1 solSelection compiled with
  | .error e =>
      expect (e.code == "PF-REQ-UNSUPPORTED" &&
          e.message.contains "effect.asynchronous-workflow")
        s!"legacy Solana must reject the first unsupported call family, got {e.render}"
  | .ok _ =>
      throw <| IO.userError "legacy Solana unexpectedly supports external effects"
  -- #125: exact CPI profile admits sync; ExtFlow still fails closed because it
  -- also requests async (unsupported) — report async first.
  let solCpiSel ← liftResult <|
    resolveBuildSelectionV1 TargetId.solana (some CodegenProfileId.solanaSbpfCpiElfV1)
  match Targets.resolveEngineeringRequirementsV1 solCpiSel compiled with
  | .error e =>
      expect (e.code == "PF-REQ-UNSUPPORTED" &&
          e.message.contains "effect.asynchronous-workflow")
        s!"cpi Solana ExtFlow must still reject async first, got {e.render}"
  | .ok _ =>
      throw <| IO.userError
        "cpi Solana unexpectedly accepted ExtFlow (includes async workflow)"
  let noirSelection ← liftResult <| resolveBuildSelectionV1 TargetId.noir none
  let noirCapability ← liftResult <|
    Targets.resolveEngineeringRequirementsV1 noirSelection compiled
  let noirPlan ← liftResult <| Targets.Noir.planFromCapability noirCapability
  match noirPlan.relations[1]!.body[1]? with
  | some (stmt : Targets.Noir.Statement) =>
      match stmt with
      | .externalCall 1 #["Oracle", "feed"] #[.stateLoad 0] => pure ()
      | _ => throw <| IO.userError "Noir bump must keep the verbatim call statement"
  | none => throw <| IO.userError "Noir bump body is too short"
  let noirInputs := noirPlan.relations[1]!.inputs
  expect (noirInputs.size == 9 && noirInputs[7]!.name == "call_e1_status" &&
      noirInputs[8]!.name == "call_e1_a0")
    "Noir bump envelope must bind the status witness and call arg slot"

  -- LaterFlow is schedule-only: EVM, NEAR, and Noir support it; legacy Solana rejects it.
  let laterSource ← liftResult (← session.selectProgramV1
    laterFlowSourceTextV1 "<targets-later-flow>" "Tests.Targets.LaterFlow" none)
  let laterCompiled ← liftResult <| Compiler.compileValidatedSourceV1 laterSource
  let evmLaterSel ← liftResult <| resolveBuildSelectionV1 TargetId.evm none
  let evmLaterCap ← liftResult <|
    Targets.resolveEngineeringRequirementsV1 evmLaterSel laterCompiled
  let evmLaterPlan ← liftResult <| Targets.Evm.planFromCapability evmLaterCap
  match evmLaterPlan.entries[0]!.body[0]? with
  | some (stmt : Targets.Evm.Statement) =>
      match stmt with
      | .schedule #["ledger", "daily"] #[.storageLoad 0] => pure ()
      | _ => throw <| IO.userError "EVM later must keep schedule ledger.daily"
  | none => throw <| IO.userError "EVM later body is too short"
  let solLaterSel ← liftResult <| resolveBuildSelectionV1 TargetId.solana none
  match Targets.resolveEngineeringRequirementsV1 solLaterSel laterCompiled with
  | .error e =>
      expect (e.code == "PF-REQ-UNSUPPORTED" &&
          e.message.contains "effect.asynchronous-workflow")
        s!"legacy Solana must reject async workflow exactly, got {e.render}"
  | .ok _ =>
      throw <| IO.userError "legacy Solana unexpectedly supports schedule"
  let nearSelection ← liftResult <| resolveBuildSelectionV1 TargetId.near none
  let nearCapability ← liftResult <|
    Targets.resolveEngineeringRequirementsV1 nearSelection laterCompiled
  let nearPlan ← liftResult <| Targets.Near.planFromCapability nearCapability
  match nearPlan.entries[0]!.body[0]? with
  | some (stmt : Targets.Near.Statement) =>
      match stmt with
      | .promiseAccount "ledger.daily" "daily" #[.stateLoad 0] => pure ()
      | _ => throw <| IO.userError "NEAR later must lower the promise account form"
  | none => throw <| IO.userError "NEAR later body is too short"
  let nearLaterIR ← liftResult <| Targets.Near.irFromCapability nearCapability
  match Targets.Near.validateWATModuleHostImportsV1 nearLaterIR with
  | .ok () => pure ()
  | .error error =>
      throw <| IO.userError
        s!"production schedule NEAR IR must retain its promise host imports: {error.render}"
  let nearOutput ← liftResult <| materializeSelected TargetId.near laterCompiled
  let some wat := nearOutput.files.find? (·.path == "LaterFlow.wat") |
    throw <| IO.userError "call-schedule: missing LaterFlow.wat"
  expect (wat.contents.contains "promise_batch_create" &&
      wat.contents.contains "ledger.daily")
    "NEAR WAT must render the promise host and the verbatim account id"
  let noirLaterSelection ← liftResult <| resolveBuildSelectionV1 TargetId.noir none
  let noirLaterCapability ← liftResult <|
    Targets.resolveEngineeringRequirementsV1 noirLaterSelection laterCompiled
  let noirLaterPlan ← liftResult <| Targets.Noir.planFromCapability noirLaterCapability
  match noirLaterPlan.relations[1]!.body[0]? with
  | some (stmt : Targets.Noir.Statement) =>
      match stmt with
      | .schedule 0 #["ledger", "daily"] #[.stateLoad 0] => pure ()
      | _ => throw <| IO.userError "Noir later must keep the schedule statement"
  | none => throw <| IO.userError "Noir later body is too short"
  -- Extra ten from probe; ExtFlow emit + void call + schedule lighthouse.
  -- EVM/Noir admit. Others stay named FC. Not opening call/schedule;
  -- existing EVM/Noir/NEAR/Solana Plan pins unchanged. B-CALL-SEM stays open.
  for target in [TargetId.evm, TargetId.noir] do
    let out ← liftResult <| materializeSelected target compiled
    expect (!(MaterializedArtifactsV1.filesOf out).isEmpty)
      s!"ExtFlow: {target} must materialize"
  for target in [TargetId.solana, TargetId.psy, TargetId.aleo, TargetId.quint,
      TargetId.soroban, TargetId.openvm] do
    match materializeSelected target compiled with
    | .error (.unsupportedRequirementV1 message) =>
        expect (message.contains "effect.asynchronous-workflow")
          s!"ExtFlow/{target}: expected effect.asynchronous-workflow, got {message}"
    | .error error =>
        throw <| IO.userError
          s!"ExtFlow/{target}: expected PF-REQ-UNSUPPORTED, got {error.render}"
    | .ok _ =>
        throw <| IO.userError
          s!"ExtFlow/{target}: materialization must fail closed"
  match materializeSelected TargetId.ton compiled with
  | .error (.unsupportedRequirementV1 message) =>
      expect (message.contains "effect.synchronous-call")
        s!"ExtFlow/ton: expected effect.synchronous-call, got {message}"
  | .error error =>
      throw <| IO.userError
        s!"ExtFlow/ton: expected PF-REQ-UNSUPPORTED, got {error.render}"
  | .ok _ =>
      throw <| IO.userError "ExtFlow/ton: materialization must fail closed"
  match materializeSelected TargetId.icp compiled with
  | .error (.unsupportedRequirementV1 message) =>
      expect (message.contains "effect.event")
        s!"ExtFlow/icp: expected effect.event, got {message}"
  | .error error =>
      throw <| IO.userError
        s!"ExtFlow/icp: expected PF-REQ-UNSUPPORTED, got {error.render}"
  | .ok _ =>
      throw <| IO.userError "ExtFlow/icp: materialization must fail closed"
  expectMaterializePlanInvariantV1 "ExtFlow" TargetId.near TargetKind.near
    compiled "synchronous external calls are outside the NEAR envelope"
  expectMaterializePlanInvariantV1 "ExtFlow" TargetId.cosmwasm TargetKind.cosmwasm
    compiled "call/sync external call is outside the CosmWasm MVP envelope"
  -- LaterFlow schedule-only from probe. EVM/NEAR/Noir/CW/TON admit.
  -- Solana/Psy/Aleo/Quint/Soroban/OpenVM decline effect.asynchronous-workflow.
  -- ICP advertises async at resolver only. Not opening schedule;
  -- existing LaterFlow Plan pins unchanged. B-CALL-SEM stays open.
  for target in [TargetId.evm, TargetId.near, TargetId.noir,
      TargetId.cosmwasm, TargetId.ton] do
    let out ← liftResult <| materializeSelected target laterCompiled
    expect (!(MaterializedArtifactsV1.filesOf out).isEmpty)
      s!"LaterFlow: {target} must materialize"
  for target in [TargetId.solana, TargetId.psy, TargetId.aleo, TargetId.quint,
      TargetId.soroban, TargetId.openvm] do
    match materializeSelected target laterCompiled with
    | .error (.unsupportedRequirementV1 message) =>
        expect (message.contains "effect.asynchronous-workflow")
          s!"LaterFlow/{target}: expected effect.asynchronous-workflow, got {message}"
    | .error error =>
        throw <| IO.userError
          s!"LaterFlow/{target}: expected PF-REQ-UNSUPPORTED, got {error.render}"
    | .ok _ =>
        throw <| IO.userError
          s!"LaterFlow/{target}: materialization must fail closed"
  expectMaterializePlanInvariantV1 "LaterFlow" TargetId.icp TargetKind.icp
    laterCompiled "ICP-2 Plan has no realized async shape"

-- Fast regression for the retained-V1 target Plan seam and fail-closed tables.
set_option maxRecDepth 10000 in
unsafe def runSemanticPlanLeafFast : IO Unit := do
  testSemanticPlanSourceAuthority
  testConstInvariantMaterializationBoundary
  testStringInterfaceMaterializationFailClosed
  testIntForMaterializationFailClosed
  testAnonymousResultMaterializationFailClosed
  testRichUInt64SemanticPlans
  testGuardedStateCellSemanticPlans
  testBoolPredicateSemanticPlans
  testBranchingSemanticPlans
  testEmitRevertSemanticPlans
  testFnLocalCallSemanticPlans
  testArithOpsSemanticPlans
  testForLoopSemanticPlans
  testShiftBitwiseLogicalSemanticPlans
  testCallScheduleSemanticPlans
  testNoirHugeFoldedShiftCount

/-- ProgramV1 BoolPredicate source text for the Bool-result leaf. -/
private def repeatedByte (count : Nat) (value : UInt8) : ByteArray :=
  ByteArray.mk (Array.replicate count value)

private partial def nestedPlanExpr : Nat → Targets.Evm.Expr
  | 0 => .literal 0
  | level + 1 => .checkedAdd (nestedPlanExpr level) (.literal 0)

private partial def fullPlanExpr : Nat → Targets.Evm.Expr
  | 0 => .literal 0
  | level + 1 =>
      let child := fullPlanExpr level
      .checkedAdd child child

private partial def nestedSolanaPlanExpr : Nat → Targets.Solana.Expr
  | 0 => .literal 0
  | level + 1 => .checkedAdd (nestedSolanaPlanExpr level) (.literal 0)

private partial def fullSolanaPlanExpr : Nat → Targets.Solana.Expr
  | 0 => .literal 0
  | level + 1 =>
      let child := fullSolanaPlanExpr level
      .checkedAdd child child

private partial def nestedNearPlanExpr : Nat → Targets.Near.Expr
  | 0 => .literal 0
  | level + 1 => .checkedAdd (nestedNearPlanExpr level) (.literal 0)

private partial def fullNearPlanExpr : Nat → Targets.Near.Expr
  | 0 => .literal 0
  | level + 1 =>
      let child := fullNearPlanExpr level
      .checkedAdd child child

private partial def nestedNoirPlanExpr : Nat → Targets.Noir.Expr
  | 0 => .literal 0
  | level + 1 => .checkedAdd (nestedNoirPlanExpr level) (.literal 0)

/-- Independent engineering Noir descriptor hash preimage golden.
Kept test-local so production serialization and its oracle cannot drift together. -/
private def noirDescriptorEngineeringReprBaseline : String :=
  "{ targetId := ProofForgeV2.TargetId.noir,\n" ++
  "  artifactEncoding := ProofForgeV2.ArtifactEncoding.noirSource,\n" ++
  "  executionHost := \"noir-circuit\",\n" ++
  "  commitModel := \"relation-external\",\n" ++
  "  stateBinding := \"external-public-pre-post\",\n" ++
  "  callModel := \"no-native-call\",\n" ++
  "  proofModel := \"external-circuit\",\n" ++
  "  settlementModel := \"external-verifier\",\n" ++
  "  codegenProfile := \"noir-source-u64-relations-v1\" }"

/-- Independent single-semantic-carrier Accumulator Noir planHash golden.
    Wave C: init relation bodies now carry the explicit `.returnNone`
    bare-return marker, which is part of the planHash preimage.
    N2b: StateField/Param gain `inputType` (u64/bool/field); UInt64 programs
    pin `.u64` and rehash the preimage.
    Noir private-witness redesign: StateField gains `visibility` (public
    programs pin `.verifier`); rehash the preimage.
    D3-E9: descriptor axes now use registry-owned V1 wire values. -/
private def accumulatorPlanHashBaseline : String :=
  "e2b2a8353a26c86707af9d17a7a26861a8a67e18aac3d6fa26f9a701040437ef"

set_option maxRecDepth 10000 in
unsafe def runProductLighthouse : IO Unit := do
  -- Product path: real ValidatedSourceV1 StateCell through the capability aggregate.
  -- All six target Plan bodies consume retained SemanticProgramV1; residual-only
  -- alpha fixtures (privateWitness/out-of-S1) cannot enter the shipped Plan surface.
  -- Host-model PrivateSum4 remains isolated test-local characterization, while
  -- capability Accumulator and rich Ledger cover production target consumers.
  let session ← Tests.Language.ParserSession.shared
  let stateCellV1 ← liftResult (← session.selectProgramV1
    Examples.stateCellSourceText "<targets-product-stateCell>"
    Examples.stateCellModuleNameV1 none)
  let stateCellCompiled ← liftResult <| Compiler.compileValidatedSourceV1 stateCellV1
  let stateCellSourceDigest := CompiledSemanticV1.sourceDigestOf stateCellCompiled
  let stateCellSemanticDigest := CompiledSemanticV1.semanticDigestOf stateCellCompiled
  expect (Targets.Evm.Keccak.keccak256Hex ByteArray.empty ==
      "c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470")
    "EVM selector hashing must use Ethereum Keccak-256, not SHA3-256"
  expect (Targets.Evm.Keccak.keccak256Hex (repeatedByte 135 0x61) ==
      "34367dc248bbd832f4e3e69dfaac2f92638bd0bbd18f2912ba4ef454919cf446")
    "Keccak padding must merge 0x01 and 0x80 at the 135-byte boundary"
  expect (Targets.Evm.Keccak.keccak256Hex (repeatedByte 136 0x61) ==
      "a6c4d403279fe3e0af03729caada8374b5ca54d8065329a3ebcaeb4b60aa386e")
    "Keccak padding must append a new block at the 136-byte rate boundary"
  expect (Targets.Evm.Keccak.keccak256Hex (repeatedByte 137 0x61) ==
      "d869f639c7046b4929fc92a4d988a8b22c55fbadb802c0c66ebcd484f1915f39")
    "Keccak hashing must preserve the first byte after a full rate block"
  expect (Targets.Evm.Keccak.selector "increment" #["uint64"] == "dd9a82bc")
    "increment(uint64) selector must match the Solidity ABI"
  expect (Targets.Evm.Keccak.selector "get" #[] == "6d4ce63c")
    "get() selector must match the Solidity ABI"
  expect (Targets.Evm.Keccak.selector "add" #["uint64"] == "7b881196")
    "add(uint64) selector must match the Solidity ABI"
  expect (Targets.Evm.Keccak.selector "current" #[] == "9fa6a6e3")
    "current() selector must match the Solidity ABI"
  expect (Targets.Evm.Keccak.selector
      "abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz"
      #["uint64"] == "7e355592")
    "EVM selector hashing must absorb signatures longer than one Keccak rate block"
  -- Product aggregate: CompiledSemanticV1 only (no bare-alpha materializeResult).
  -- Extra eight from probe; public UInt64 StateCell is the shared lighthouse.
  -- All twelve implemented targets admit. Not opening a new type/capability.
  for target in [TargetId.evm, TargetId.solana, TargetId.near, TargetId.noir,
      TargetId.aleo, TargetId.psy, TargetId.quint, TargetId.cosmwasm,
      TargetId.ton, TargetId.soroban, TargetId.openvm, TargetId.icp] do
    let output ← liftResult <| materializeSelected target stateCellCompiled
    expect (!(MaterializedArtifactsV1.filesOf output).isEmpty)
      s!"{target} must emit at least one artifact"
    expect (MaterializedArtifactsV1.sourceDigestOf output == stateCellSourceDigest)
      "product carrier must bind the canonical ValidatedSourceV1 digest"
    expect (MaterializedArtifactsV1.semanticDigestOf output == stateCellSemanticDigest)
      "product carrier must bind the retained SemanticProgramV1 digest"
  -- S6: alpha-direct materialize remains closed; product capability path covers StateCell.
  -- Current engineering capability claims / privateWitness inspection (not residual planFromAlpha).
  -- PrivateSum4 host accept/reject: Tests.Materialization.NoirRelationModel fixture.
  let privateWitnessReq : RequirementRequestV1 := {
    id := "disclosure.private-witness"
    version := s2RequirementVersionV1
    digest := zeroDigest
    predicates := #[]
  }
  let evmSelection ← liftResult <| resolveBuildSelectionV1 TargetId.evm none
  let evmSupport ← liftResult <|
    inspectSupportWithSeedV1 initialStaticRequirementSupportIndexV1Result
      evmSelection.targetId evmSelection.codegenProfile
  match inspectResolveRequestsV1 evmSupport.supported { items := #[privateWitnessReq] } with
  | .error e =>
      expect (e.code == "PF-REQ-UNSUPPORTED")
        s!"EVM product support must reject private-witness, got {e.render}"
  | .ok _ =>
      throw <| IO.userError "EVM must reject private-witness on product support inspection"
  -- AddressBearing currently advertises the canonical static-QN sync-call key.
  -- This records the engineering claim only; B-CALL-SEM still decides whether
  -- partial EVM CALL semantics remain supported or are conservatively downgraded.
  let syncCallReq ← match mkS2RequirementRequestV1 "effect.synchronous-call" with
    | .ok request => pure request
    | .error message =>
        throw <| IO.userError s!"canonical synchronous-call request failed: {message}"
  match inspectResolveRequestsV1 evmSupport.supported { items := #[syncCallReq] } with
  | .ok () => pure ()
  | .error error =>
      throw <| IO.userError
        s!"EVM current engineering claim must admit canonical synchronous-call: {error.render}"
  -- A malformed digest must not masquerade as evidence that the key itself is
  -- unsupported; it is a distinct exact-request negative.
  let malformedSyncCallReq := { syncCallReq with digest := zeroDigest }
  match inspectResolveRequestsV1 evmSupport.supported
      { items := #[malformedSyncCallReq] } with
  | .error error =>
      expect (error.code == "PF-REQ-UNSUPPORTED" && error.render.contains "digest")
        s!"EVM malformed synchronous-call request must fail digest matching, got {error.render}"
  | .ok () =>
      throw <| IO.userError
        "EVM malformed synchronous-call digest must fail product support inspection"
  -- Single-semantic capability files + capability-gated plan for Accumulator.
  let accSession ← Tests.Language.ParserSession.shared
  let accSource ← liftResult (← accSession.selectProgramV1
    accumulatorSourceTextV1 "<targets-accumulator>" accumulatorModuleNameV1 none)
  let accCompiled ← liftResult <| Compiler.compileValidatedSourceV1 accSource
  let accumulatorOutput ← liftResult <| materializeSelected TargetId.evm accCompiled
  let accumulatorPlan ← liftResult <| planEvm accCompiled


  -- Cross-kind capability → planFromCapability negatives (kind gate).
  let evmCap ← liftResult <| (do
    let sel ← resolveBuildSelectionV1 TargetId.evm none
    Targets.resolveEngineeringRequirementsV1 sel accCompiled)
  match Targets.Solana.planFromCapability evmCap with
  | .error (.planInvariant .solana _) => pure ()
  | .error e => throw <| IO.userError s!"Solana cross-kind must planInvariant, got {e.render}"
  | .ok _ => throw <| IO.userError "Solana must reject EVM capability kind"
  match Targets.Near.planFromCapability evmCap with
  | .error (.planInvariant .near _) => pure ()
  | _ => throw <| IO.userError "NEAR must reject EVM capability kind"
  match Targets.Noir.planFromCapability evmCap with
  | .error (.planInvariant .noir _) => pure ()
  | _ => throw <| IO.userError "Noir must reject EVM capability kind"
  match Targets.Evm.planFromCapability evmCap with
  | .ok _ => pure ()
  | .error e => throw <| IO.userError s!"EVM capability plan must succeed: {e.render}"
  expect (accumulatorPlan.storageLayout.size == 1 &&
      accumulatorPlan.storageLayout[0]!.name == "total" &&
      accumulatorPlan.storageLayout[0]!.slot == 0)
    "EvmPlan must own Accumulator storage layout"
  expect (accumulatorPlan.entries.map (·.name) == #["add", "current"])
    "EvmPlan must preserve every semantic entry"
  let addEntry := accumulatorPlan.entries[0]!
  let depth256Entries := accumulatorPlan.entries.set! 0 {
    addEntry with body := #[.returnValue (nestedPlanExpr 255)]
  }
  match Targets.Evm.validatePlan { accumulatorPlan with entries := depth256Entries } with
  | .ok () => pure ()
  | _ => throw <| IO.userError "EvmPlan must accept expression depth 256"
  let depth257Entries := accumulatorPlan.entries.set! 0 {
    addEntry with body := #[.returnValue (nestedPlanExpr 256)]
  }
  match Targets.Evm.validatePlan { accumulatorPlan with entries := depth257Entries } with
  | .error (.planInvariant .evm _) => pure ()
  | _ => throw <| IO.userError "EvmPlan must reject expression depth 257"
  let oversizedExprEntries := accumulatorPlan.entries.set! 0 {
    addEntry with body := #[.returnValue (fullPlanExpr 16)]
  }
  match Targets.Evm.validatePlan { accumulatorPlan with entries := oversizedExprEntries } with
  | .error (.planInvariant .evm _) => pure ()
  | _ => throw <| IO.userError "EvmPlan must reject aggregate expression nodes above 100000"
  let collidedEntries := accumulatorPlan.entries.set! 1 {
    accumulatorPlan.entries[1]! with selector := accumulatorPlan.entries[0]!.selector
  }
  match Targets.Evm.validatePlan { accumulatorPlan with entries := collidedEntries } with
  | .error (.planInvariant .evm _) => pure ()
  | _ => throw <| IO.userError "EvmPlan must reject selector collisions"
  let wrongSelectorEntries := accumulatorPlan.entries.set! 0 {
    accumulatorPlan.entries[0]! with selector := "00000000"
  }
  match Targets.Evm.validatePlan { accumulatorPlan with entries := wrongSelectorEntries } with
  | .error (.planInvariant .evm _) => pure ()
  | _ => throw <| IO.userError "EvmPlan must bind dispatch selectors to canonical ABI signatures"
  let constructor := accumulatorPlan.constructor.get!
  let danglingStores := constructor.stores.set! 0 { constructor.stores[0]! with slot := 99 }
  match Targets.Evm.validatePlan {
      accumulatorPlan with constructor := some { constructor with stores := danglingStores }
    } with
  | .error (.planInvariant .evm _) => pure ()
  | _ => throw <| IO.userError "EvmPlan must reject dangling storage slots"
  let unsafeParams := constructor.params.set! 0 { constructor.params[0]! with name := "\t" }
  match Targets.Evm.validatePlan {
      accumulatorPlan with constructor := some { constructor with params := unsafeParams }
    } with
  | .error (.planInvariant .evm _) => pure ()
  | _ => throw <| IO.userError "EvmPlan must reject unsafe ABI parameter names"
  let falseOriginParams := constructor.params.set! 0 { constructor.params[0]! with sourceId := 99 }
  match Targets.Evm.validatePlan {
      accumulatorPlan with constructor := some { constructor with params := falseOriginParams }
    } with
  | .error (.planInvariant .evm _) => pure ()
  | _ => throw <| IO.userError "EvmPlan must reject forged semantic parameter origins"
  let noncontiguousLayout := accumulatorPlan.storageLayout.set! 0 {
    accumulatorPlan.storageLayout[0]! with slot := 1024
  }
  match Targets.Evm.validatePlan { accumulatorPlan with storageLayout := noncontiguousLayout } with
  | .error (.planInvariant .evm _) => pure ()
  | _ => throw <| IO.userError "EvmPlan must reject non-canonical storage slots"
  let falseOriginLayout := accumulatorPlan.storageLayout.set! 0 {
    accumulatorPlan.storageLayout[0]! with sourceId := 99
  }
  match Targets.Evm.validatePlan { accumulatorPlan with storageLayout := falseOriginLayout } with
  | .error (.planInvariant .evm _) => pure ()
  | _ => throw <| IO.userError "EvmPlan must reject forged semantic state origins"
  match Targets.Evm.validatePlan {
      accumulatorPlan with runtimeObjectName := accumulatorPlan.objectName
    } with
  | .error (.planInvariant .evm _) => pure ()
  | _ => throw <| IO.userError "EvmPlan must keep nested object identities distinct"
  let maximumArtifactStem := String.ofList (List.replicate 231 'a')
  match Targets.Evm.validatePlan { accumulatorPlan with objectName := maximumArtifactStem } with
  | .ok () => pure ()
  | _ => throw <| IO.userError "EvmPlan must accept a 231-byte artifact stem"
  let tooLongArtifactStem := String.ofList (List.replicate 232 'a')
  match Targets.Evm.validatePlan { accumulatorPlan with objectName := tooLongArtifactStem } with
  | .error (.planInvariant .evm _) => pure ()
  | _ => throw <| IO.userError "EvmPlan must reserve suffix bytes within the 240-byte output path limit"
  -- Wave 2 EVM pilot: Plan construction now consumes retained SemanticProgramV1
  -- only. Public Plan mutation negatives below continue to pin target-owned depth,
  -- identity, and resource invariants; no alpha Semantic→Plan test seam remains.
  let accumulatorYul ← match accumulatorOutput.files.find? (·.path == "Accumulator.yul") with
    | some file => pure file.contents
    | none => throw <| IO.userError "EVM Accumulator must emit Yul"
  let accumulatorAbi ← match accumulatorOutput.files.find? (·.path == "Accumulator.abi.json") with
    | some file => pure file.contents
    | none => throw <| IO.userError "EVM Accumulator must emit ABI"
  expect (accumulatorYul.contains "case 0x7b881196")
    "EVM must derive the add(uint64) Keccak selector"
  expect (accumulatorYul.contains "case 0x9fa6a6e3")
    "EVM must derive the current() Keccak selector"
  expect (accumulatorAbi.contains "\"name\":\"add\"")
    "EVM ABI must be derived from Accumulator entries"
  expect (!accumulatorAbi.contains "increment")
    "EVM ABI must not retain the StateCell template"

  -- Capability-gated Solana plan for single-semantic carrier Accumulator.
  let solanaPlan ← liftResult <| planSolana accCompiled
  -- Forged/unknown profile is not product-selectable (selection authority).
  let forgedSolanaProfile ← parseProfileFixture "forged-profile"
  match resolveBuildSelectionV1 TargetId.solana (some forgedSolanaProfile) with
  | .error e =>
      expect (e.code == "PF-PROFILE-UNKNOWN" || e.code == "PF-REGISTRY-INVALID" ||
          e.code.startsWith "PF-PROFILE" || e.code.startsWith "PF-TARGET")
        s!"forged Solana profile must fail selection, got {e.render}"
  | .ok _ =>
      throw <| IO.userError "Solana must reject a forged/unknown codegen profile at selection"
  expect (solanaPlan.stateAccount.exactDataLen == 16 &&
      solanaPlan.stateAccount.headerOffset == 0 &&
      solanaPlan.stateAccount.initializedMarker == 0xb298024662f2309a &&
      solanaPlan.stateAccount.payloadInitialization == .zeroAllFields &&
      solanaPlan.stateAccount.fields.size == 1 &&
      solanaPlan.stateAccount.fields[0]!.name == "total" &&
      solanaPlan.stateAccount.fields[0]!.byteOffset == 8)
    "SolanaPlan must own the initialized header and Accumulator UInt64 layout"
  match Targets.Solana.validatePlan {
      solanaPlan with arithmeticOverflowError := 0
    } with
  | .error (.planInvariant .solana _) => pure ()
  | _ => throw <| IO.userError "SolanaPlan must own its stable arithmetic error mapping"
  expect (solanaPlan.initializer.name == "initialize" &&
      solanaPlan.initializer.params[0]!.name == "seed" &&
      solanaPlan.initializer.params[0]!.dataOffset == 8 &&
      solanaPlan.initializer.accountAccess.signerRequired &&
      solanaPlan.initializer.accountAccess.writableRequired)
    "SolanaPlan must own initializer wire/account requirements"
  expect (solanaPlan.entries.map (·.name) == #["add", "current"] &&
      solanaPlan.entries[0]!.accountAccess.writableRequired &&
      !solanaPlan.entries[1]!.accountAccess.writableRequired)
    "SolanaPlan must derive mutable and readonly account metas per entry"
  expect (solanaPlan.initializer.discriminator == "5e494767a7582864" &&
      solanaPlan.entries[0]!.discriminator == "2999f319c883ec76" &&
      solanaPlan.entries[1]!.discriminator == "8c07d3938c593e21")
    "Solana instruction discriminators must match independent SHA-256 goldens"
  let solanaAdd := solanaPlan.entries[0]!
  let solanaDepth256 := solanaPlan.entries.set! 0 {
    solanaAdd with body := #[.returnValue (nestedSolanaPlanExpr 255)]
  }
  match Targets.Solana.validatePlan { solanaPlan with entries := solanaDepth256 } with
  | .ok () => pure ()
  | _ => throw <| IO.userError "SolanaPlan must accept expression depth 256"
  let solanaDepth257 := solanaPlan.entries.set! 0 {
    solanaAdd with body := #[.returnValue (nestedSolanaPlanExpr 256)]
  }
  match Targets.Solana.validatePlan { solanaPlan with entries := solanaDepth257 } with
  | .error (.planInvariant .solana _) => pure ()
  | _ => throw <| IO.userError "SolanaPlan must reject expression depth 257"
  let solanaOversized := solanaPlan.entries.set! 0 {
    solanaAdd with body := #[.returnValue (fullSolanaPlanExpr 16)]
  }
  match Targets.Solana.validatePlan { solanaPlan with entries := solanaOversized } with
  | .error (.planInvariant .solana _) => pure ()
  | _ => throw <| IO.userError "SolanaPlan must reject aggregate expression nodes above 100000"
  let wrongSolanaDiscriminator := solanaPlan.entries.set! 0 {
    solanaAdd with discriminator := "0000000000000000"
  }
  match Targets.Solana.validatePlan {
      solanaPlan with entries := wrongSolanaDiscriminator
    } with
  | .error (.planInvariant .solana _) => pure ()
  | _ => throw <| IO.userError "SolanaPlan must bind discriminators to canonical signatures"
  let collidedSolanaDiscriminator := solanaPlan.entries.set! 1 {
    solanaPlan.entries[1]! with discriminator := solanaAdd.discriminator
  }
  match Targets.Solana.validatePlan {
      solanaPlan with entries := collidedSolanaDiscriminator
    } with
  | .error (.planInvariant .solana _) => pure ()
  | _ => throw <| IO.userError "SolanaPlan must reject discriminator collisions"
  match Targets.Solana.validatePlan {
      solanaPlan with stateAccount := { solanaPlan.stateAccount with exactDataLen := 8 }
    } with
  | .error (.planInvariant .solana _) => pure ()
  | _ => throw <| IO.userError "SolanaPlan must reject an undersized state account"
  match Targets.Solana.validatePlan {
      solanaPlan with stateAccount := {
        solanaPlan.stateAccount with initializedMarker := 0
      }
    } with
  | .error (.planInvariant .solana _) => pure ()
  | _ => throw <| IO.userError "SolanaPlan must reserve zero exclusively for uninitialized accounts"
  let maximumSolanaStem := String.ofList (List.replicate 230 's')
  match Targets.Solana.validatePlan { solanaPlan with programName := maximumSolanaStem } with
  | .ok () => pure ()
  | _ => throw <| IO.userError "SolanaPlan must accept a 230-byte artifact stem"
  let oversizedSolanaStem := String.ofList (List.replicate 231 's')
  match Targets.Solana.validatePlan { solanaPlan with programName := oversizedSolanaStem } with
  | .error (.planInvariant .solana _) => pure ()
  | _ => throw <| IO.userError "SolanaPlan must reserve the .s/.cpi-plan.json suffix within 240 bytes"
  let readonlyAdd := {
    solanaAdd with accountAccess := {
      solanaAdd.accountAccess with writableRequired := false
    }
  }
  match Targets.Solana.validatePlan {
      solanaPlan with entries := solanaPlan.entries.set! 0 readonlyAdd
    } with
  | .error (.planInvariant .solana _) => pure ()
  | _ => throw <| IO.userError "SolanaPlan must reject missing writable access for a mutating entry"
  let viewStore := {
    solanaPlan.entries[1]! with
    body := #[.store {
      accountIndex := 0
      byteOffset := 8
      value := .literal 1
    }, .returnValue (.literal 1)]
  }
  match Targets.Solana.validatePlan {
      solanaPlan with entries := solanaPlan.entries.set! 1 viewStore
    } with
  | .error (.planInvariant .solana _) => pure ()
  | _ => throw <| IO.userError "SolanaPlan must reject a view entry that stores state"
  let falseSolanaParam := {
    solanaPlan.initializer.params[0]! with sourceId := 9
  }
  match Targets.Solana.validatePlan {
      solanaPlan with initializer := {
        solanaPlan.initializer with
        params := solanaPlan.initializer.params.set! 0 falseSolanaParam
      }
    } with
  | .error (.planInvariant .solana _) => pure ()
  | _ => throw <| IO.userError "SolanaPlan must reject forged parameter origins"
  -- Solana capability Plan body is retained-SemanticProgramV1-native; typed IR
  -- remains inspected only through production irFromCapability.
  let solanaIR ← liftResult <| irSolana accCompiled
  expect (solanaIR.handlers[0]!.operations[0]? ==
      some (Targets.Solana.Operation.zeroState 0 8))
    "Solana initializer IR must zero state payload before applying semantic stores"
  let removedChecks := solanaIR.handlers.set! 0 {
    solanaIR.handlers[0]! with checks := #[]
  }
  match Targets.Solana.validateIR (Targets.Solana.withHandlers solanaIR removedChecks) with
  | .error (.planInvariant .solana _) => pure ()
  | _ => throw <| IO.userError "Solana typed IR must reject missing account/data/init checks"
  let forgedCurrentOperations := #[
    Targets.Solana.Operation.literal 0 99,
    Targets.Solana.Operation.setReturnData 8 0
  ]
  let forgedCurrentHandler := {
    solanaIR.handlers[2]! with operations := forgedCurrentOperations
  }
  match Targets.Solana.validateIR
      (Targets.Solana.withHandlers solanaIR
        (solanaIR.handlers.set! 2 forgedCurrentHandler)) with
  | .error (.planInvariant .solana _) => pure ()
  | _ => throw <| IO.userError "Solana typed IR must remain exactly bound to its source Plan"
  -- Multi-field partial-init/read-other shapes remain S1 Normalize fail-closed;
  -- former alpha Core.Semantics hand-built characterization removed with the
  -- alpha residual modules.

  let nearPlan ← liftResult <| planNear accCompiled
  -- forgedNearDescriptor still used for validatePlan descriptor-binding negatives.
  let forgedNearProfile ← parseProfileFixture "forged-profile"
  let forgedNearDescriptor := {
    Targets.Near.descriptor with codegenProfile := forgedNearProfile
  }
  expect (nearPlan.storage.fields.size == 1 &&
      nearPlan.storage.fields[0]!.sourceId == 0 &&
      nearPlan.storage.fields[0]!.name == "total" &&
      nearPlan.storage.fields[0]!.key == "pf:v1:state:0" &&
      nearPlan.storage.markerKey == "pf:v1:layout" &&
      nearPlan.storage.markerValue != 0)
    "NearPlan must own the Accumulator KV layout and layout-bound marker"
  expect (nearPlan.initializer.name == "init" &&
      nearPlan.initializer.params[0]!.name == "seed" &&
      nearPlan.initializer.exactInputLen == 8 &&
      nearPlan.initializer.depositPolicy == .requireZero &&
      nearPlan.entries.map (·.name) == #["add", "current"] &&
      nearPlan.entries[0]!.depositPolicy == .requireZero &&
      nearPlan.entries[1]!.depositPolicy == .queryOnly &&
      nearPlan.entries[1]!.exactInputLen == 0)
    "NearPlan must own dynamic exports, exact raw input, mode, and deposit policies"
  expect (nearPlan.hostImports.size == 9 &&
      nearPlan.hostImports.contains .attachedDeposit &&
      nearPlan.hostImports.contains .logUtf8 &&
      nearPlan.hostImports.contains .panicUtf8 &&
      nearPlan.failurePolicy.invalidInput == .trap &&
      nearPlan.failurePolicy.corruptStorage == .trap &&
      nearPlan.failurePolicy.arithmeticOverflow == .trap &&
      nearPlan.commitPolicy == .rollbackOnTrap &&
      nearPlan.resourceLimits.maxMethodLocals == 50000 &&
      nearPlan.resourceLimits.wasmMemoryPages == 1)
    "NearPlan must own its host allowlist, failure/receipt policy, and resource envelope"
  match Targets.Near.validatePlan {
      nearPlan with targetDescriptor := forgedNearDescriptor
    } with
  | .error (.planInvariant .near _) => pure ()
  | _ => throw <| IO.userError "NearPlan must reject a forged descriptor/profile"
  match Targets.Near.validatePlan { nearPlan with hostImports := #[] } with
  | .error (.planInvariant .near _) => pure ()
  | _ => throw <| IO.userError "NearPlan must reject a forged host-import allowlist"
  match Targets.Near.validatePlan {
      nearPlan with failurePolicy := {
        nearPlan.failurePolicy with invalidInput := .returnStatus
      }
    } with
  | .error (.planInvariant .near _) => pure ()
  | _ => throw <| IO.userError "NearPlan must reject a forged failure policy"
  match Targets.Near.validatePlan {
      nearPlan with commitPolicy := .retainWritesOnTrap
    } with
  | .error (.planInvariant .near _) => pure ()
  | _ => throw <| IO.userError "NearPlan must reject a non-rollback receipt policy"
  match Targets.Near.validatePlan {
      nearPlan with resourceLimits := {
        nearPlan.resourceLimits with maxMethodLocals := 50001
      }
    } with
  | .error (.planInvariant .near _) => pure ()
  | _ => throw <| IO.userError "NearPlan must reject a forged resource envelope"
  match Targets.Near.validatePlan {
      nearPlan with storage := { nearPlan.storage with markerValue := 0 }
    } with
  | .error (.planInvariant .near _) => pure ()
  | _ => throw <| IO.userError "NearPlan must reserve zero for an absent layout marker"
  let forgedNearField := {
    nearPlan.storage.fields[0]! with key := "fixed-stateCell-key"
  }
  match Targets.Near.validatePlan {
      nearPlan with storage := {
        nearPlan.storage with fields := nearPlan.storage.fields.set! 0 forgedNearField
      }
    } with
  | .error (.planInvariant .near _) => pure ()
  | _ => throw <| IO.userError "NearPlan must reject a forged target-owned KV binding"
  let nearViewStore := {
    nearPlan.entries[1]! with
    body := #[.store { fieldIndex := 0, value := .literal 1 }, .returnValue (.literal 1)]
  }
  match Targets.Near.validatePlan {
      nearPlan with entries := nearPlan.entries.set! 1 nearViewStore
    } with
  | .error (.planInvariant .near _) => pure ()
  | _ => throw <| IO.userError "NearPlan must reject a view method that writes KV state"
  let nearMemoryExport := { nearPlan.entries[1]! with name := "memory" }
  match Targets.Near.validatePlan {
      nearPlan with entries := nearPlan.entries.set! 1 nearMemoryExport
    } with
  | .error (.planInvariant .near _) => pure ()
  | _ => throw <| IO.userError "NearPlan must reject collision with the exported Wasm memory"
  let forgedNearParam := {
    nearPlan.initializer.params[0]! with sourceId := 9
  }
  match Targets.Near.validatePlan {
      nearPlan with initializer := {
        nearPlan.initializer with
        params := nearPlan.initializer.params.set! 0 forgedNearParam
      }
    } with
  | .error (.planInvariant .near _) => pure ()
  | _ => throw <| IO.userError "NearPlan must reject forged semantic parameter origins"
  let wrongNearDeposit := {
    nearPlan.entries[0]! with depositPolicy := .queryOnly
  }
  match Targets.Near.validatePlan {
      nearPlan with entries := nearPlan.entries.set! 0 wrongNearDeposit
    } with
  | .error (.planInvariant .near _) => pure ()
  | _ => throw <| IO.userError "NearPlan must reject a mutable method without zero-deposit policy"
  let nearAdd := nearPlan.entries[0]!
  let unboundNearLocal := {
    nearAdd with body := #[.returnValue (.localTemp 0)]
  }
  match Targets.Near.validatePlan {
      nearPlan with entries := nearPlan.entries.set! 0 unboundNearLocal
    } with
  | .error (.planInvariant .near _) => pure ()
  | _ =>
      throw <| IO.userError
        "NEAR Plan validation must reject a method localTemp without a for-loop binder"
  let validNearLoop : Targets.Near.Statement :=
    .forLoop 0 (.literal 0)
      (.compare .lt (.localTemp 0) (.literal 1))
      (.checkedAdd (.localTemp 0) (.literal 1)) 1 #[]
  let validNestedNearLoop : Targets.Near.Statement :=
    .forLoop 0 (.literal 0)
      (.compare .lt (.localTemp 0) (.literal 1))
      (.checkedAdd (.localTemp 0) (.literal 1)) 1 #[
        .forLoop 1 (.localTemp 0)
          (.compare .le (.localTemp 1) (.localTemp 0))
          (.checkedAdd (.localTemp 1) (.literal 1)) 1 #[
            .assert (.compare .le (.localTemp 0) (.localTemp 1))],
        .assert (.compare .le (.localTemp 0) (.literal 1))]
  let validNestedNearLoopMethod := {
    nearAdd with body := #[validNestedNearLoop, .returnValue (.literal 0)]
  }
  match Targets.Near.validatePlan {
      nearPlan with entries := nearPlan.entries.set! 0 validNestedNearLoopMethod
    } with
  | .ok () => pure ()
  | .error error =>
      throw <| IO.userError
        s!"NEAR Plan validation must accept lexically bound nested loop locals: {error.render}"
  let unboundNearLoopInitial := {
    nearAdd with body := #[
      .forLoop 0 (.localTemp 0)
        (.compare .lt (.localTemp 0) (.literal 1))
        (.checkedAdd (.localTemp 0) (.literal 1)) 1 #[],
      .returnValue (.literal 0)]
  }
  match Targets.Near.validatePlan {
      nearPlan with entries := nearPlan.entries.set! 0 unboundNearLoopInitial
    } with
  | .error (.planInvariant .near _) => pure ()
  | _ =>
      throw <| IO.userError
        "NEAR Plan validation must reject a for-loop binder in its own initial expression"
  let escapedNearLoopLocal := {
    nearAdd with body := #[validNearLoop, .returnValue (.localTemp 0)]
  }
  match Targets.Near.validatePlan {
      nearPlan with entries := nearPlan.entries.set! 0 escapedNearLoopLocal
    } with
  | .error (.planInvariant .near _) => pure ()
  | _ =>
      throw <| IO.userError
        "NEAR Plan validation must reject a for-loop local after its lexical scope"
  let shadowedNearLoopLocal := {
    nearAdd with body := #[
      .forLoop 0 (.literal 0)
        (.compare .lt (.localTemp 0) (.literal 1))
        (.checkedAdd (.localTemp 0) (.literal 1)) 1 #[validNearLoop],
      .returnValue (.literal 0)]
  }
  match Targets.Near.validatePlan {
      nearPlan with entries := nearPlan.entries.set! 0 shadowedNearLoopLocal
    } with
  | .error (.planInvariant .near _) => pure ()
  | _ =>
      throw <| IO.userError
        "NEAR Plan validation must reject nested induction-local shadowing"
  let nearDepth256 := nearPlan.entries.set! 0 {
    nearAdd with body := #[.returnValue (nestedNearPlanExpr 255)]
  }
  match Targets.Near.validatePlan { nearPlan with entries := nearDepth256 } with
  | .ok () => pure ()
  | _ => throw <| IO.userError "NearPlan must accept expression depth 256"
  let nearDepth257 := nearPlan.entries.set! 0 {
    nearAdd with body := #[.returnValue (nestedNearPlanExpr 256)]
  }
  match Targets.Near.validatePlan { nearPlan with entries := nearDepth257 } with
  | .error (.planInvariant .near _) => pure ()
  | _ => throw <| IO.userError "NearPlan must reject expression depth 257"
  let nearOversized := nearPlan.entries.set! 0 {
    nearAdd with body := #[.returnValue (fullNearPlanExpr 16)]
  }
  match Targets.Near.validatePlan { nearPlan with entries := nearOversized } with
  | .error (.planInvariant .near _) => pure ()
  | _ => throw <| IO.userError "NearPlan must reject aggregate expression nodes above 100000"
  let nearTooManyLocals := nearPlan.entries.set! 0 {
    nearAdd with body := #[.returnValue (fullNearPlanExpr 15)]
  }
  match Targets.Near.validatePlan { nearPlan with entries := nearTooManyLocals } with
  | .error (.planInvariant .near _) => pure ()
  | _ => throw <| IO.userError "NearPlan must reject methods above NEAR's 50000-local limit"
  -- S6 removed public residual Plan routes; the NEAR capability Plan body now
  -- consumes retained SemanticProgramV1 through the target-private S1 lowering.
  -- Capability NEAR IR via production irFromCapability.
  let nearIR ← liftResult <| irNear accCompiled
  let nearMarker := nearIR.keys[0]!
  let nearField := nearIR.keys[1]!
  expect (nearIR.methods[0]!.operations == #[
      .checkInputLen 8,
      .requireZeroAttachedDeposit,
      .requireLayoutAbsent nearMarker,
      .zeroState nearField,
      .loadParam 0 0,
      .storeState nearField 0,
      .setLayout nearMarker nearPlan.storage.markerValue
    ])
    "NEAR initializer recipe must check input/deposit/layout, zero state, apply init, then mark layout"
  expect (nearIR.methods[1]!.operations == #[
      .checkInputLen 8,
      .requireZeroAttachedDeposit,
      .requireLayout nearMarker nearPlan.storage.markerValue,
      .loadState 0 nearField,
      .loadParam 1 0,
      .checkedAdd 2 0 1,
      .storeState nearField 2,
      .loadState 3 nearField,
      .setReturnData 8 3
    ])
    "NEAR mutable recipe must preserve checked Accumulator statement order"
  expect (nearIR.methods[2]!.operations == #[
      .checkInputLen 0,
      .requireLayout nearMarker nearPlan.storage.markerValue,
      .loadState 0 nearField,
      .setReturnData 8 0
    ])
    "NEAR view recipe must require empty input/layout and contain no deposit or write operation"
  let forgedNearOperations := #[
    Targets.Near.Operation.checkInputLen 0,
    .requireLayout nearMarker nearPlan.storage.markerValue,
    .literal 0 99,
    .setReturnData 8 0
  ]
  let forgedNearMethod := {
    nearIR.methods[2]! with operations := forgedNearOperations
  }
  match Targets.Near.validateIR
      (Targets.Near.withMethods nearIR (nearIR.methods.set! 2 forgedNearMethod)) with
  | .error (.planInvariant .near _) => pure ()
  | _ => throw <| IO.userError "typed NEAR recipe must remain exactly bound to its source Plan"
  match Targets.Near.validateWATModuleMethodExportsV1 nearIR with
  | .ok () => pure ()
  | .error error =>
      throw <| IO.userError
        s!"production NEAR IR must pass method/export validation: {error.render}"
  let renamedNearMethod := {
    nearIR.methods[2]! with name := "forgedCurrent"
  }
  match Targets.Near.validateWATModuleMethodExportsV1
      (Targets.Near.withMethods nearIR
        (nearIR.methods.set! 2 renamedNearMethod)) with
  | .error (.planInvariant .near _) => pure ()
  | _ =>
      throw <| IO.userError
        "NEAR WAT module validation must reject a forged method export name"
  let reorderedNearMethods :=
    (nearIR.methods.set! 1 nearIR.methods[2]!).set! 2 nearIR.methods[1]!
  let reorderedNearIR := Targets.Near.withMethods nearIR reorderedNearMethods
  match Targets.Near.validateWATModuleMethodExportsV1 reorderedNearIR with
  | .error (.planInvariant .near _) => pure ()
  | _ =>
      throw <| IO.userError
        "NEAR WAT module validation must reject reordered method exports"
  match Targets.Near.validateIR reorderedNearIR with
  | .error (.planInvariant .near _) => pure ()
  | _ =>
      throw <| IO.userError
        "production NEAR IR validation must reject reordered method exports"
  let forgedNearMethodSignature := {
    nearIR.methods[0]! with params := #[]
  }
  match Targets.Near.validateWATModuleMethodExportsV1
      (Targets.Near.withMethods nearIR
        (nearIR.methods.set! 0 forgedNearMethodSignature)) with
  | .error (.planInvariant .near _) => pure ()
  | _ =>
      throw <| IO.userError
        "NEAR WAT module validation must reject forged method ABI metadata"
  let forgedNearMethodMode := {
    nearIR.methods[2]! with mode := Targets.Near.MethodMode.mutate
  }
  match Targets.Near.validateWATModuleMethodExportsV1
      (Targets.Near.withMethods nearIR
        (nearIR.methods.set! 2 forgedNearMethodMode)) with
  | .error (.planInvariant .near _) => pure ()
  | _ =>
      throw <| IO.userError
        "NEAR WAT module validation must reject a forged method mode"
  match Targets.Near.validateWATModuleLocalReferencesV1 nearIR with
  | .ok () => pure ()
  | .error error =>
      throw <| IO.userError
        s!"production NEAR IR must pass numeric-local reference validation: {error.render}"
  let outOfRangeNearLocal := nearIR.methods[2]!.tempCount
  let forgedNearLocalMethod := {
    nearIR.methods[2]! with
    operations := #[.setReturnData 8 outOfRangeNearLocal]
  }
  match Targets.Near.validateWATModuleLocalReferencesV1
      (Targets.Near.withMethods nearIR
        (nearIR.methods.set! 2 forgedNearLocalMethod)) with
  | .error (.planInvariant .near _) => pure ()
  | _ =>
      throw <| IO.userError
        "NEAR WAT module validation must reject a top-level undeclared numeric local"
  let forgedNestedNearLocalMethod := {
    nearIR.methods[2]! with
    operations := #[.ifRegion 0
      #[.literal outOfRangeNearLocal 1] #[]]
  }
  match Targets.Near.validateWATModuleLocalReferencesV1
      (Targets.Near.withMethods nearIR
        (nearIR.methods.set! 2 forgedNestedNearLocalMethod)) with
  | .error (.planInvariant .near _) => pure ()
  | _ =>
      throw <| IO.userError
        "NEAR WAT module validation must inspect nested numeric-local references"
  let forgedWideLocalFn : Targets.Near.FnIR := {
    name := "forgedWideLocal"
    paramCount := 0
    resultIsBool := false
    tempCount := 4
    operations := #[.narrowBitNot 128 3 0]
  }
  match Targets.Near.validateWATModuleLocalReferencesV1
      (Targets.Near.withFns nearIR #[forgedWideLocalFn]) with
  | .error (.planInvariant .near _) => pure ()
  | _ =>
      throw <| IO.userError
        "NEAR WAT module validation must reject an undeclared pureFn multiword limb"
  match Targets.Near.validateWATModuleHostImportsV1 nearIR with
  | .ok () => pure ()
  | .error error =>
      throw <| IO.userError
        s!"production NEAR IR must pass canonical host-import validation: {error.render}"
  let undeclaredPromiseImportFn : Targets.Near.FnIR := {
    name := "forgedPromiseImport"
    paramCount := 0
    resultIsBool := false
    tempCount := 0
    operations := #[.promiseAccount "aa" "call" #[]]
  }
  match Targets.Near.validateWATModuleHostImportsV1
      (Targets.Near.withFns nearIR #[undeclaredPromiseImportFn]) with
  | .error (.planInvariant .near _) => pure ()
  | _ =>
      throw <| IO.userError
        "NEAR WAT module validation must reject an undeclared promise host dependency"
  let undeclaredNestedImportFn : Targets.Near.FnIR := {
    name := "forgedNestedImport"
    paramCount := 0
    resultIsBool := false
    tempCount := 1
    operations := #[.ifRegion 0 #[.blockTimestampSeconds 0] #[]]
  }
  match Targets.Near.validateWATModuleHostImportsV1
      (Targets.Near.withFns nearIR #[undeclaredNestedImportFn]) with
  | .error (.planInvariant .near _) => pure ()
  | _ =>
      throw <| IO.userError
        "NEAR WAT module validation must inspect nested operation host dependencies"
  match Targets.Near.validateWATModuleMemoryV1 nearIR with
  | .ok () => pure ()
  | .error error =>
      throw <| IO.userError
        s!"production NEAR IR must pass complete WAT module memory validation: {error.render}"
  let oversizedPromiseString :=
    String.ofList (List.replicate Targets.Near.wasmPageBytes 'a')
  let oversizedPromiseDataFn : Targets.Near.FnIR := {
    name := "forgedPromiseData"
    paramCount := 0
    resultIsBool := false
    tempCount := 0
    operations := #[.promiseAccount oversizedPromiseString "call" #[]]
  }
  match Targets.Near.validateWATModuleMemoryV1
      (Targets.Near.withFns nearIR #[oversizedPromiseDataFn]) with
  | .error (.planInvariant .near _) => pure ()
  | _ =>
      throw <| IO.userError
        "NEAR WAT module validation must reject promise data beyond declared memory"
  let oversizedPromiseScratchFn : Targets.Near.FnIR := {
    name := "forgedPromiseScratch"
    paramCount := 0
    resultIsBool := false
    tempCount := 1
    operations := #[.promiseAccount "aa" "call"
      (Array.replicate 129 0)]
  }
  match Targets.Near.validateWATModuleMemoryV1
      (Targets.Near.withFns nearIR #[oversizedPromiseScratchFn]) with
  | .error (.planInvariant .near _) => pure ()
  | _ =>
      throw <| IO.userError
        "NEAR WAT module validation must reject operation scratch overlapping promise data"
  let malformedReturnLeavesFn : Targets.Near.FnIR := {
    name := "forgedReturnLeaves"
    paramCount := 0
    resultIsBool := false
    tempCount := 129
    operations := #[.setReturnDataLeaves (Array.replicate 129 0) #[1]]
  }
  match Targets.Near.validateWATModuleMemoryV1
      (Targets.Near.withFns nearIR #[malformedReturnLeavesFn]) with
  | .error (.planInvariant .near _) => pure ()
  | _ =>
      throw <| IO.userError
        "NEAR WAT module validation must account for every rendered return-leaf store"
  -- The fast S1 seam pins multi-field retained-V1 Plan ordering. The exact WAT
  -- golden below remains the capability Accumulator materialization (complete
  -- bytes rather than a multi-field substring oracle).

  -- Capability-gated single-semantic Noir plan (sole product Plan authority).
  let noirPlan ← liftResult <| planNoir accCompiled
  let noirCapPlan := noirPlan
  expect (noirCapPlan.states == #[{ sourceId := 0, name := "total" }] &&
      noirCapPlan.relations.map (·.name) == #["init", "add", "current"])
    "capability Noir plan must preserve Accumulator state and relation catalog"
  let forgedNoirProfile ← parseProfileFixture "forged-profile"
  let forgedNoirDescriptor := {
    Targets.Noir.descriptor with codegenProfile := forgedNoirProfile
  }
  -- Registry-owned descriptor-axis preimage must be explicit V1 wire and
  -- independent of opaque structure Repr; support is not part of this identity.
  expect (Targets.Noir.targetDescriptorEngineeringReprV1 Targets.Noir.descriptor ==
      noirDescriptorEngineeringReprBaseline)
    "Noir descriptor engineering wire must equal its independent baseline"
  let opaqueRepr := reprStr Targets.Noir.descriptor
  expect ((opaqueRepr.splitOn "value :=").length > 1)
    "opaque TargetId Repr must not become the engineering descriptor wire"
  -- Canonical compiled source/semantic digests feed the complete planHash.
  let accSourceHash ← liftResult <| CompiledSemanticV1.artifactSourceHashHexOf accCompiled
  let accSemanticHash ← liftResult <| CompiledSemanticV1.artifactSemanticHashHexOf accCompiled
  expect (noirPlan.planHash == accumulatorPlanHashBaseline)
    s!"capability Noir planHash must match the single-semantic baseline, got {noirPlan.planHash}"
  expect (noirPlan.sourceHash == accSourceHash &&
      noirPlan.semanticHash == accSemanticHash &&
      noirPlan.states == #[{ sourceId := 0, name := "total" }] &&
      noirPlan.continuity == .externalPublicPrePost &&
      noirPlan.proofStatus == .notProduced &&
      noirPlan.relations.map (·.name) == #["init", "add", "current"] &&
      noirPlan.relations.map (·.mode) == #[.initialize, .mutate, .view])
    "NoirPlan must own the full Accumulator init/mutate/view relation catalog"
  expect (noirPlan.relations[0]!.inputs.map (·.name) ==
      #["pre_initialized", "arg_p0", "post_s0", "post_initialized"] &&
      noirPlan.relations[1]!.inputs.map (·.name) ==
        #["pre_initialized", "pre_s0", "arg_p0", "post_s0", "post_initialized", "result"] &&
      noirPlan.relations[2]!.inputs.map (·.name) ==
        #["pre_initialized", "pre_s0", "post_s0", "post_initialized", "result"])
    "NoirPlan must expose lifecycle, pre/post state, parameters, and result explicitly"
  let zeroDigest := String.ofList (List.replicate 64 '0')
  match Targets.Noir.validatePlan { noirPlan with sourceHash := zeroDigest } with
  | .error (.planInvariant .noir _) => pure ()
  | _ => throw <| IO.userError "NoirPlan must bind its source hash into the complete Plan hash"
  match Targets.Noir.validatePlan { noirPlan with semanticHash := zeroDigest } with
  | .error (.planInvariant .noir _) => pure ()
  | _ => throw <| IO.userError "NoirPlan must bind its semantic hash into the complete Plan hash"
  match Targets.Noir.validatePlan { noirPlan with programName := "ForgedAccumulator" } with
  | .error (.planInvariant .noir _) => pure ()
  | _ => throw <| IO.userError "NoirPlan must bind its program identity into the complete Plan hash"
  match Targets.Noir.validatePlan {
      noirPlan with targetDescriptor := forgedNoirDescriptor
    } with
  | .error (.planInvariant .noir _) => pure ()
  | _ => throw <| IO.userError "NoirPlan must reject a forged target descriptor"
  match Targets.Noir.validatePlan {
      noirPlan with continuity := .none
    } with
  | .error (.planInvariant .noir _) => pure ()
  | _ => throw <| IO.userError "NoirPlan must reject erased external state continuity"
  match Targets.Noir.validatePlan {
      noirPlan with resourceLimits := {
        noirPlan.resourceLimits with maxRelations := 257
      }
    } with
  | .error (.planInvariant .noir _) => pure ()
  | _ => throw <| IO.userError "NoirPlan must reject a forged resource envelope"
  let excessiveNoirParams := Array.replicate
    (noirPlan.resourceLimits.maxParams + 1) noirPlan.relations[1]!.params[0]!
  let excessiveNoirParamRelation := {
    noirPlan.relations[1]! with params := excessiveNoirParams
  }
  match Targets.Noir.validatePlan {
      noirPlan with relations := noirPlan.relations.set! 1 excessiveNoirParamRelation
    } with
  | .error (.planInvariant .noir _) => pure ()
  | _ => throw <| IO.userError "NoirPlan must enforce the per-relation parameter limit"
  let forgedNoirInput := {
    noirPlan.relations[1]!.inputs[2]! with visibility := .witness
  }
  let forgedNoirRelation := {
    noirPlan.relations[1]! with
    inputs := noirPlan.relations[1]!.inputs.set! 2 forgedNoirInput
  }
  match Targets.Noir.validatePlan {
      noirPlan with relations := noirPlan.relations.set! 1 forgedNoirRelation
    } with
  | .error (.planInvariant .noir _) => pure ()
  | _ => throw <| IO.userError "NoirPlan must reject forged public/private disclosure"
  let forgedNoirView := {
    noirPlan.relations[2]! with body := #[
      .store { fieldIndex := 0, value := .literal 1 },
      .returnValue (.stateLoad 0)
    ]
  }
  match Targets.Noir.validatePlan {
      noirPlan with relations := noirPlan.relations.set! 2 forgedNoirView
    } with
  | .error (.planInvariant .noir _) => pure ()
  | _ => throw <| IO.userError "NoirPlan must reject a view relation that writes state"
  let deepNoirStore := Targets.Noir.Statement.store {
    fieldIndex := 0
    value := nestedNoirPlanExpr (noirPlan.resourceLimits.maxExprDepth + 1)
  }
  let deepNoirRelation := {
    noirPlan.relations[1]! with
    body := noirPlan.relations[1]!.body.set! 0 deepNoirStore
  }
  match Targets.Noir.validatePlan {
      noirPlan with relations := noirPlan.relations.set! 1 deepNoirRelation
    } with
  | .error (.planInvariant .noir _) => pure ()
  | _ => throw <| IO.userError "NoirPlan must reject deep expressions before hashing the Plan"
  -- S6 removed public residual Plan/IR/files routes. The Noir capability Plan
  -- body now consumes retained SemanticProgramV1; capability Accumulator IR +
  -- exact materialize goldens cover the downstream product surface.
  -- S1 cannot express literal-return different-logic or privateWitness dead-arith fixtures.

  let noirIR ← liftResult <| irNoir accCompiled
  expect (noirIR.relations[0]!.operations == #[
      .assertBool 0 false,
      .assertEqual (.input 2) (.input 1),
      .assertBool 3 true
    ])
    "Noir initializer relation must prove zero-origin initialization and lifecycle false-to-true"
  expect (noirIR.relations[1]!.operations == #[
      .assertBool 0 true,
      .checkedAdd 0 (.input 1) (.input 2),
      .assertEqual (.input 3) (.temp 0),
      .assertBool 4 true,
      .assertEqual (.input 5) (.temp 0)
    ])
    "Noir mutate relation must bind checked add to post-state/result and lifecycle true-to-true"
  expect (noirIR.relations[2]!.operations == #[
      .assertBool 0 true,
      .assertEqual (.input 2) (.input 1),
      .assertBool 3 true,
      .assertEqual (.input 4) (.input 1)
    ])
    "Noir view relation must preserve pre/post state and bind its public result"
  let forgedNoirOperations := noirIR.relations[1]!.operations.set! 1
    (.checkedAdd 0 (.input 1) (.literal 99))
  let forgedNoirIRRelation := {
    noirIR.relations[1]! with operations := forgedNoirOperations
  }
  match Targets.Noir.validateIR
      (Targets.Noir.withRelations noirIR
        (noirIR.relations.set! 1 forgedNoirIRRelation)) with
  | .error (.planInvariant .noir _) => pure ()
  | _ => throw <| IO.userError "typed Noir IR must remain exactly bound to its source Plan"
  let oversizedNoirIRRelation := {
    noirIR.relations[1]! with
    tempCount := noirPlan.resourceLimits.maxIrOperations + 1
  }
  match Targets.Noir.validateIR
      (Targets.Noir.withRelations noirIR
        (noirIR.relations.set! 1 oversizedNoirIRRelation)) with
  | .error (.planInvariant .noir _) => pure ()
  | _ => throw <| IO.userError "typed Noir IR must stop at the operation resource limit"

  -- Dual-carrier capability materialize for Accumulator artifacts (four targets).
  -- Exact complete WAT / Noir source bytes from real materializeResult (not
  -- reimplemented renderer): fixed independent length/hash or full string +
  -- repeat determinism + canonical file order + trailing newline.
  let nearAccumulator ← liftResult <| materializeSelected TargetId.near accCompiled
  expect (nearAccumulator.files.map (·.path) ==
      #["Accumulator.wat", "Accumulator.near-abi.json"])
    "NEAR Accumulator must emit WAT then ABI in canonical order"
  let nearWat ← match nearAccumulator.files[0]? with
    | some f =>
        expect (f.path == "Accumulator.wat") "NEAR first file must be Accumulator.wat"
        pure f.contents
    | none => throw <| IO.userError "missing Accumulator.wat"
  let nearAccumulator2 ← liftResult <| materializeSelected TargetId.near accCompiled
  let nearWat2 ← match nearAccumulator2.files.find? (·.path == "Accumulator.wat") with
    | some f => pure f.contents
    | none => throw <| IO.userError "missing Accumulator.wat (repeat)"
  expect (nearWat == nearWat2)
    "NEAR Accumulator WAT must be repeat-deterministic"
  expect (nearWat.endsWith "\n" && nearWat.startsWith "(module\n")
    "NEAR Accumulator WAT must start with module header and end with trailing newline"
  expect (nearWat.toUTF8.size == accumulatorNearWatExactUtf8Len)
    s!"NEAR Accumulator WAT UTF-8 length must equal fixed golden {accumulatorNearWatExactUtf8Len}, got {nearWat.toUTF8.size}"
  expect (Crypto.sha256Hex nearWat.toUTF8 == accumulatorNearWatSha256Hex)
    s!"NEAR Accumulator WAT SHA-256 must equal fixed golden {accumulatorNearWatSha256Hex}, got {Crypto.sha256Hex nearWat.toUTF8}"
  let noirAccumulator ← liftResult <| materializeSelected TargetId.noir accCompiled
  expect (noirAccumulator.files.map (·.path) ==
      #[
        "Accumulator.noir-relations.json",
        "relations/r0-init/src/main.nr",
        "relations/r0-init/Nargo.toml",
        "relations/r1-add/src/main.nr",
        "relations/r1-add/Nargo.toml",
        "relations/r2-current/src/main.nr",
        "relations/r2-current/Nargo.toml"
      ])
    "Noir Accumulator must emit catalog then relation packages in canonical order"
  let noirAdd ← match noirAccumulator.files.find?
      (·.path == "relations/r1-add/src/main.nr") with
    | some f => pure f.contents
    | none => throw <| IO.userError "missing Noir add relation source"
  let noirAccumulator2 ← liftResult <| materializeSelected TargetId.noir accCompiled
  let noirAdd2 ← match noirAccumulator2.files.find?
      (·.path == "relations/r1-add/src/main.nr") with
    | some f => pure f.contents
    | none => throw <| IO.userError "missing Noir add relation source (repeat)"
  expect (noirAdd == noirAdd2)
    "Noir Accumulator add relation must be repeat-deterministic"
  expect (noirAdd == accumulatorNoirAddExactSource)
    "Noir Accumulator add relation must equal independent fixed complete source golden"
  expect (noirAdd.endsWith "\n")
    "Noir Accumulator add relation must end with trailing newline"
  let solanaAccumulator ← liftResult <| materializeSelected TargetId.solana accCompiled
  expect (solanaAccumulator.files.map (·.path) ==
      #["Accumulator.cpi-plan.json", "Accumulator.cpi-ir.json", "Accumulator.idl.json", "Accumulator.s", "Accumulator.cpi-bindings.json"])
    "Solana Accumulator must emit plan then IDL in canonical order"
  -- Extra eight from probe; public UInt64 Accumulator lighthouse. Eleven
  -- materialize. Aleo declines reserved entry name `add`. Not opening a
  -- rename/shape; existing four-target goldens unchanged.
  for target in [TargetId.evm, TargetId.solana, TargetId.near, TargetId.noir,
      TargetId.psy, TargetId.quint, TargetId.cosmwasm, TargetId.ton,
      TargetId.soroban, TargetId.openvm, TargetId.icp] do
    let out ← liftResult <| materializeSelected target accCompiled
    expect (!(MaterializedArtifactsV1.filesOf out).isEmpty)
      s!"Accumulator: {target} must materialize"
  expectMaterializePlanInvariantV1 "Accumulator" TargetId.aleo TargetKind.aleo
    accCompiled "reserved Aleo Instructions identifier"

  -- Real EVM product negative: selectProgramV1 succeeds; compileValidatedSourceV1
  -- fails exactly at disclosure PF-VIS-001. selection/capability/materialize must
  -- not run; no output files.
  let privateReturnSource :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program PrivateReturn where\n" ++
    "  entry leak(private secret : UInt64) : UInt64 do\n" ++
    "    return secret\n\n" ++
    "end ProofForgeV2.Examples\n"
  let mut phaseSelectOk := false
  let mut phaseCompileVisFail := false
  let mut phaseSelectionCalled := false
  let mut phaseCapabilityCalled := false
  let mut phaseMaterializeCalled := false
  let mut emittedFiles : Array String := #[]
  match ← session.selectProgramV1 privateReturnSource
      "<targets-evm-product-negative>" "Examples.PrivateReturn" none with
  | .error e =>
      throw <| IO.userError
        s!"EVM product negative selectProgramV1 must succeed, got {e.render}"
  | .ok privSource =>
      phaseSelectOk := true
      match Compiler.compileValidatedSourceV1 privSource with
      | .error (.visibilityViolation message) =>
          expect (message.contains
              "disclosure violation: cannot flow 'private' into 'public'")
            s!"EVM product negative must use disclosure detail, got {message}"
          expect (CompileError.code (.visibilityViolation message) == "PF-VIS-001")
            "EVM product negative wire code must be PF-VIS-001"
          phaseCompileVisFail := true
          -- Explicitly do not call selection / capability / materialize after
          -- compile fail. Flags remain false; files accumulator stays empty.
      | .error other =>
          throw <| IO.userError
            s!"EVM product negative compile must be exact PF-VIS-001 visibilityViolation, got {other.render}"
      | .ok privCompiled =>
          -- Must not reach product materialize path for this negative.
          phaseSelectionCalled := true
          let sel ← liftResult <| resolveBuildSelectionV1 TargetId.evm none
          phaseCapabilityCalled := true
          match Targets.resolveEngineeringRequirementsV1 sel privCompiled with
          | .error e =>
              throw <| IO.userError
                s!"EVM product negative must fail at compile PF-VIS-001, not later resolve {e.render}"
          | .ok cap =>
              phaseMaterializeCalled := true
              match Targets.materializeResult cap with
              | .ok out =>
                  emittedFiles := out.files.map (·.path)
                  throw <| IO.userError
                    s!"EVM product negative must not emit files, got {emittedFiles}"
              | .error e =>
                  throw <| IO.userError
                    s!"EVM product negative must fail at compile PF-VIS-001, not materialize {e.render}"
  expect phaseSelectOk "EVM product negative: selectProgramV1 phase must succeed"
  expect phaseCompileVisFail
    "EVM product negative: compile phase must fail exact PF-VIS-001"
  expect (!phaseSelectionCalled && !phaseCapabilityCalled && !phaseMaterializeCalled)
    "EVM product negative: selection/capability/materialize must not be called after compile fail"
  expect emittedFiles.isEmpty
    "EVM product negative: files accumulator must stay empty"

  -- N1 + Noir private-witness redesign: private state in layout + public
  -- return compiles and materializes on EVM/Solana/NEAR/Psy/Aleo and Noir
  -- (private pre/post state slots are private-witness inputs; public count
  -- remains verifier-visible).
  -- T-1 authority/custody: entry private writes require context.caller evidence
  -- (and ContextRead is target Plan fail-closed). Keep private writes in init
  -- only so product compile + target materialize still pin private layout.
  let privateStateSource :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program PrivWrite where\n" ++
    "  state count : UInt64\n" ++
    "  state private secret : UInt64\n\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "    secret := 0\n\n" ++
    "  entry bump(d : UInt64) : UInt64 do\n" ++
    "    count := count + d\n" ++
    "    return count\n\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n\n" ++
    "end ProofForgeV2.Examples\n"
  let privStateV1 ← match ← session.selectProgramV1 privateStateSource
      "<targets-n1-priv-state>" "Examples.PrivWrite" none with
    | .ok v => pure v
    | .error e => throw <| IO.userError s!"N1 priv-state select: {e.render}"
  let privStateCompiled ← liftResult <| Compiler.compileValidatedSourceV1 privStateV1
  let privStateData ← match validateSemanticProgramV1
      (CompiledSemanticV1.semanticV1Of privStateCompiled) with
    | .ok d => pure d
    | .error e => throw <| IO.userError s!"N1 priv-state semantic: {repr e}"
  expect (privStateData.logicalState.size == 2)
    "N1 priv-state: two logical states"
  expect (privStateData.logicalState.any fun s =>
      s.name == "secret" && s.visibility == .private_)
    "N1 priv-state: secret retains private visibility"
  -- Extra six from probe; not disclosure redesign.
  for target in [TargetId.evm, TargetId.solana, TargetId.near, TargetId.psy, TargetId.aleo,
      TargetId.noir, TargetId.cosmwasm, TargetId.ton] do
    let out ← liftResult <| materializeSelected target privStateCompiled
    expect (!(MaterializedArtifactsV1.filesOf out).isEmpty)
      s!"N1 priv-state: {target} must materialize"
  for target in [TargetId.quint, TargetId.soroban, TargetId.icp, TargetId.openvm] do
    match materializeSelected target privStateCompiled with
    | .ok _ =>
        throw <| IO.userError s!"N1 priv-state: {target} must decline private state"
    | .error e =>
        expect ((e.render).contains "private" ||
            (e.render).contains "visibility" ||
            (e.render).contains "unsupported" ||
            (e.render).contains "pilot" ||
            (e.render).contains "public" ||
            (e.render).contains "secret")
          s!"N1 priv-state {target} message must cite private/visibility boundary, got {e.render}"
  let noirPrivState ← liftResult <| planNoir privStateCompiled
  expect (noirPrivState.states.any fun s =>
      s.name == "secret" && s.visibility == .witness)
    "N1 priv-state: Noir Plan maps private state to witness slots"
  expect (noirPrivState.states.any fun s =>
      s.name == "count" && s.visibility == .verifier)
    "N1 priv-state: Noir Plan keeps public state verifier-visible"
  -- secret is written in init only (T-1: no entry private write without caller).
  -- Any relation that carries secret pre/post slots must mark them witness.
  let mut secretWitnessSlots : Nat := 0
  for rel in noirPrivState.relations do
    for i in rel.inputs do
      match i.role with
      | .preState sid | .postState sid =>
          match noirPrivState.states[sid]? with
          | some f =>
              if f.name == "secret" then
                expect (i.visibility == .witness)
                  "N1 priv-state: Noir secret pre/post inputs must be private-witness"
                secretWitnessSlots := secretWitnessSlots + 1
          | none => pure ()
      | _ => pure ()
  expect (secretWitnessSlots ≥ 2)
    s!"N1 priv-state: expected ≥2 secret pre/post witness slots, got {secretWitnessSlots}"

  -- N1: commitment state public→commitment write + public return materializes
  -- on accepting targets (lattice: public→commitment OK). Noir still declines
  -- commitment (private-witness redesign admits private only; no public
  -- commitment binding in the relation pilot).
  let commitmentStateSource :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program CommMark where\n" ++
    "  state commitment sealed : UInt64\n\n" ++
    "  init() do\n" ++
    "    sealed := 0\n\n" ++
    "  entry mark(x : UInt64) : UInt64 do\n" ++
    "    sealed := x\n" ++
    "    return x\n\n" ++
    "end ProofForgeV2.Examples\n"
  let commStateV1 ← match ← session.selectProgramV1 commitmentStateSource
      "<targets-n1-comm-state>" "Examples.CommMark" none with
    | .ok v => pure v
    | .error e => throw <| IO.userError s!"N1 comm-state select: {e.render}"
  let commStateCompiled ← liftResult <| Compiler.compileValidatedSourceV1 commStateV1
  let commStateData ← match validateSemanticProgramV1
      (CompiledSemanticV1.semanticV1Of commStateCompiled) with
    | .ok d => pure d
    | .error e => throw <| IO.userError s!"N1 comm-state semantic: {repr e}"
  expect (commStateData.logicalState.any fun s =>
      s.name == "sealed" && s.visibility == .commitment)
    "N1 comm-state: sealed retains commitment visibility"
  -- Extra six from probe; not B-COMMIT-ZK.
  for target in [TargetId.evm, TargetId.solana, TargetId.near, TargetId.psy, TargetId.aleo,
      TargetId.cosmwasm, TargetId.ton] do
    let out ← liftResult <| materializeSelected target commStateCompiled
    expect (!(MaterializedArtifactsV1.filesOf out).isEmpty)
      s!"N1 comm-state: {target} must materialize"
  for target in [TargetId.noir, TargetId.quint, TargetId.soroban, TargetId.icp,
      TargetId.openvm] do
    match materializeSelected target commStateCompiled with
    | .ok _ =>
        throw <| IO.userError s!"N1 comm-state: {target} must decline commitment state at Plan"
    | .error e =>
        expect ((e.render).contains "commitment state" ||
            (e.render).contains "not representable" ||
            (e.render).contains "commitment binding" ||
            (e.render).contains "unsupported" ||
            (e.render).contains "pilot" ||
            (e.render).contains "public")
          s!"N1 comm-state {target} message must cite commitment boundary, got {e.render}"

  -- N1 + Noir private-witness redesign: unused private param (no public sink)
  -- compiles + materializes on EVM and Noir (private param → private-witness
  -- input; unused so no disclosure leak).
  let privateParamSource :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program PrivParam where\n" ++
    "  state count : UInt64\n\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n\n" ++
    "  entry increment(delta : UInt64, private witness : UInt64) : UInt64 do\n" ++
    "    count := count + delta\n" ++
    "    return count\n\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n\n" ++
    "end ProofForgeV2.Examples\n"
  let privParamV1 ← match ← session.selectProgramV1 privateParamSource
      "<targets-n1-priv-param>" "Examples.PrivParam" none with
    | .ok v => pure v
    | .error e => throw <| IO.userError s!"N1 priv-param select: {e.render}"
  let privParamCompiled ← liftResult <| Compiler.compileValidatedSourceV1 privParamV1
  let evmPrivParam ← liftResult <| materializeSelected TargetId.evm privParamCompiled
  expect (!(MaterializedArtifactsV1.filesOf evmPrivParam).isEmpty)
    "N1 priv-param: EVM must materialize unused private param"
  let noirPrivParamOut ← liftResult <| materializeSelected TargetId.noir privParamCompiled
  expect (!(MaterializedArtifactsV1.filesOf noirPrivParamOut).isEmpty)
    "N1 priv-param: Noir must materialize unused private param as witness"
  let noirPrivParamPlan ← liftResult <| planNoir privParamCompiled
  let witnessParamInputs := noirPrivParamPlan.relations[1]!.inputs.filter fun i =>
    match i.role with
    | .parameter _ => i.visibility == .witness
    | _ => false
  expect (witnessParamInputs.size == 1 && witnessParamInputs[0]!.sourceName == "witness")
    "N1 priv-param: Noir binds private param as private-witness input"
  -- Extra ten from probe; unused private param (no public sink). Not a
  -- disclosure redesign. Quint/Soroban/ICP/OpenVM stay public-param envelope FC.
  for target in [TargetId.solana, TargetId.near, TargetId.psy, TargetId.aleo,
      TargetId.cosmwasm, TargetId.ton] do
    let out ← liftResult <| materializeSelected target privParamCompiled
    expect (!(MaterializedArtifactsV1.filesOf out).isEmpty)
      s!"N1 priv-param: {target} must materialize unused private param"
  for target in [TargetId.quint, TargetId.soroban, TargetId.icp, TargetId.openvm] do
    match materializeSelected target privParamCompiled with
    | .ok _ =>
        throw <| IO.userError s!"N1 priv-param: {target} must decline unused private param"
    | .error e =>
        expect ((e.render).contains "private" ||
            (e.render).contains "witness" ||
            (e.render).contains "visibility" ||
            (e.render).contains "unsupported" ||
            (e.render).contains "pilot" ||
            (e.render).contains "public" ||
            (e.render).contains "param")
          s!"N1 priv-param {target} message must cite private/param boundary, got {e.render}"

  -- N2b: Field bn254_fr product pin — Noir (native Field) + EVM (ADDMOD/MULMOD
  -- + Fermat inv) admit. Extra ten from probe stay Plan FC; not opening Field.
  -- Aleo native Field is BLS12-377 Fr (not bn254); Psy Felt is Goldilocks.
  let fieldSource :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program FieldMix where\n" ++
    "  state acc : Field bn254_fr\n\n" ++
    "  init(initial : Field bn254_fr) do\n" ++
    "    acc := initial\n\n" ++
    "  entry bump(delta : Field bn254_fr) : Field bn254_fr do\n" ++
    "    acc := acc + delta\n" ++
    "    return acc\n\n" ++
    "  entry neg(x : Field bn254_fr) : Field bn254_fr do\n" ++
    "    return -x\n\n" ++
    "  entry eq(a : Field bn254_fr, b : Field bn254_fr) : Bool do\n" ++
    "    return a == b\n\n" ++
    "  view get() : Field bn254_fr do\n" ++
    "    return acc\n\n" ++
    "end ProofForgeV2.Examples\n"
  let fieldV1 ← match ← session.selectProgramV1 fieldSource
      "<targets-n2b-field>" "Examples.FieldMix" none with
    | .ok v => pure v
    | .error e => throw <| IO.userError s!"N2b field select: {e.render}"
  let fieldCompiled ← liftResult <| Compiler.compileValidatedSourceV1 fieldV1
  let noirField ← liftResult <| planNoir fieldCompiled
  expect (noirField.relations.any fun r => r.name == "bump")
    "N2b field: Noir plan must include bump relation"
  expect (noirField.relations.any fun r => r.name == "neg")
    "N2b field: Noir plan must include neg relation"
  -- At least one Field-typed input appears on the bump relation.
  let some bumpRel := noirField.relations.find? (·.name == "bump") |
    throw <| IO.userError "N2b field: missing bump relation"
  expect (bumpRel.inputs.any fun i => i.type == Targets.Noir.InputType.field)
    "N2b field: Noir bump relation must carry Field-typed inputs"
  -- EVM is the second Field lane (N2b-EVM): Plan admits Field state/params.
  let evmField ← liftResult <| planEvm fieldCompiled
  expect (evmField.storageLayout.size == 1 &&
      evmField.storageLayout[0]!.byteWidth == 32 &&
      evmField.storageLayout[0]!.name == "acc")
    "N2b field: EVM Field state must be a single 32-byte storage slot"
  expect (evmField.entries.any fun e => e.name == "bump" && e.resultKind == .field)
    "N2b field: EVM bump must return Field"
  expect (evmField.entries.any fun e => e.name == "neg" && e.resultKind == .field)
    "N2b field: EVM neg must return Field"
  let evmFieldFiles ← liftResult <| materializeSelected TargetId.evm fieldCompiled
  let some evmFieldYul :=
      (MaterializedArtifactsV1.filesOf evmFieldFiles).find? (·.path == "FieldMix.yul") |
    throw <| IO.userError "N2b field: missing FieldMix.yul"
  expect (evmFieldYul.contents.contains "addmod(" &&
      evmFieldYul.contents.contains
        "0x30644e72e131a029b85045b68181585d2833e84879b9709143e1f593f0000001")
    "N2b field: EVM Yul must emit addmod with bn254 Fr modulus"
  for target in [TargetId.solana, TargetId.near, TargetId.psy, TargetId.aleo,
      TargetId.quint, TargetId.cosmwasm, TargetId.ton, TargetId.soroban,
      TargetId.icp, TargetId.openvm] do
    match materializeSelected target fieldCompiled with
    | .ok _ =>
        throw <| IO.userError s!"N2b field: {target} must fail closed on Field"
    | .error e =>
        expect ((e.render).contains "Field" ||
            (e.render).contains "unsupported" ||
            (e.render).contains "mod-p" ||
            (e.render).contains "bn254")
          s!"N2b field {target} message must cite Field boundary, got {e.render}"
  -- PsyFelt research pin: Psy Felt is Goldilocks, not bn254 Fr — type-closure
  -- wording must name the modulus mismatch (no silent approximate mapping).
  match materializeSelected TargetId.psy fieldCompiled with
  | .ok _ =>
      throw <| IO.userError
        "N2b field: Psy must fail closed on Field (Felt is Goldilocks, not bn254 Fr)"
  | .error e =>
      expect ((e.render).contains "Goldilocks" ||
          (e.render).contains "0xFFFFFFFF00000001" ||
          (e.render).contains "2^64-2^32+1" ||
          (e.render).contains "bn254 Fr")
        s!"N2b field Psy message must cite Goldilocks≠bn254 Fr, got {e.render}"
  -- Aleo native Field is BLS12-377 Fr / Edwards BLS scalar, not bn254 Fr —
  -- same honesty class as Psy Goldilocks (no silent remapping).
  match materializeSelected TargetId.aleo fieldCompiled with
  | .ok _ =>
      throw <| IO.userError
        "N2b field: Aleo must fail closed on bn254 Fr (native Field is BLS12-377 Fr)"
  | .error e =>
      expect ((e.render).contains "bls12-377" ||
          (e.render).contains "BLS12-377" ||
          (e.render).contains "Edwards" ||
          (e.render).contains "bn254 Fr")
        s!"N2b field Aleo message must cite BLS12-377≠bn254 Fr, got {e.render}"

set_option maxRecDepth 10000 in
unsafe def runWideIntegerNeedles : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  -- WideUInt: UInt128 state/return. EVM/Solana/NEAR/Noir/Psy/Aleo/CosmWasm/TON
  -- admit. Quint/Soroban/OpenVM/ICP stay named FC. Not opening
  -- UInt256 or signed 128. Files-nonempty or Plan-invariant needles.
  let wideUIntSource :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program WideUInt where\n" ++
    "  state n : UInt128\n\n" ++
    "  init(x : UInt128) do\n" ++
    "    n := x\n\n" ++
    "  entry bump(d : UInt128) : UInt128 do\n" ++
    "    n := n + d\n" ++
    "    return n\n\n" ++
    "  view get() : UInt128 do\n" ++
    "    return n\n\n" ++
    "end ProofForgeV2.Examples\n"
  let wideV1 ← match ← session.selectProgramV1 wideUIntSource
      "<targets-uint128>" "Examples.WideUInt" none with
    | .ok v => pure v
    | .error e => throw <| IO.userError s!"WideUInt select: {e.render}"
  let wideCompiled ← liftResult <| Compiler.compileValidatedSourceV1 wideV1
  for target in [TargetId.evm, TargetId.solana, TargetId.near, TargetId.noir,
      TargetId.psy, TargetId.aleo, TargetId.cosmwasm, TargetId.ton] do
    let out ← liftResult <| materializeSelected target wideCompiled
    expect (!(MaterializedArtifactsV1.filesOf out).isEmpty)
      s!"WideUInt: {target} must materialize UInt128"
  for (target, kind) in #[
      (TargetId.quint, TargetKind.quint),
      (TargetId.soroban, TargetKind.soroban),
      (TargetId.openvm, TargetKind.openvm),
      (TargetId.icp, TargetKind.icp)] do
    expectMaterializePlanInvariantV1 "WideUInt" target kind wideCompiled
      "only anonymous UInt64/Int64 widths are supported"

  -- WideUInt256: UInt256 state/return. Seven-target files-nonempty admit
  -- (evm/solana/near/noir/psy/ton/cosmwasm). Aleo stays width FC (native u128,
  -- not u256). Quint/Soroban/OpenVM/ICP stay named FC. Not opening signed
  -- 128/256. TON is one uint256 cell / loadUint(256); CW is 4×8-byte Regions.
  let wideUInt256Source :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program WideUInt256 where\n" ++
    "  state n : UInt256\n\n" ++
    "  init(x : UInt256) do\n" ++
    "    n := x\n\n" ++
    "  entry bump(d : UInt256) : UInt256 do\n" ++
    "    n := n + d\n" ++
    "    return n\n\n" ++
    "  view get() : UInt256 do\n" ++
    "    return n\n\n" ++
    "end ProofForgeV2.Examples\n"
  let wide256V1 ← match ← session.selectProgramV1 wideUInt256Source
      "<targets-uint256>" "Examples.WideUInt256" none with
    | .ok v => pure v
    | .error e => throw <| IO.userError s!"WideUInt256 select: {e.render}"
  let wide256Compiled ← liftResult <| Compiler.compileValidatedSourceV1 wide256V1
  for target in [TargetId.evm, TargetId.solana, TargetId.near, TargetId.noir,
      TargetId.psy, TargetId.ton, TargetId.cosmwasm] do
    let out ← liftResult <| materializeSelected target wide256Compiled
    expect (!(MaterializedArtifactsV1.filesOf out).isEmpty)
      s!"WideUInt256: {target} must materialize UInt256"
  expectMaterializePlanInvariantV1 "WideUInt256" TargetId.aleo TargetKind.aleo
    wide256Compiled "only anonymous UInt64/UInt32/UInt16/UInt8/UInt128/Int64/Int32/Int16/Int8 widths are supported"
  for (target, kind) in #[
      (TargetId.quint, TargetKind.quint),
      (TargetId.soroban, TargetKind.soroban),
      (TargetId.openvm, TargetKind.openvm),
      (TargetId.icp, TargetKind.icp)] do
    expectMaterializePlanInvariantV1 "WideUInt256" target kind wide256Compiled
      "only anonymous UInt64/Int64 widths are supported"

  -- WideInt128: Int128 state/return. All twelve targets stay named width
  -- FC. Not opening Int128 or Int256. WideUInt / WideUInt256 pins stay.
  let wideInt128Source :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program WideInt128 where\n" ++
    "  state n : Int128\n\n" ++
    "  init(x : Int128) do\n" ++
    "    n := x\n\n" ++
    "  entry bump(d : Int128) : Int128 do\n" ++
    "    n := n + d\n" ++
    "    return n\n\n" ++
    "  view get() : Int128 do\n" ++
    "    return n\n\n" ++
    "end ProofForgeV2.Examples\n"
  let wideI128V1 ← match ← session.selectProgramV1 wideInt128Source
      "<targets-int128>" "Examples.WideInt128" none with
    | .ok v => pure v
    | .error e => throw <| IO.userError s!"WideInt128 select: {e.render}"
  let wideI128Compiled ← liftResult <| Compiler.compileValidatedSourceV1 wideI128V1
  expectMaterializePlanInvariantV1 "WideInt128" TargetId.evm TargetKind.evm
    wideI128Compiled "Int8/Int16/Int32/Int64 integer widths are supported"
  expectMaterializePlanInvariantV1 "WideInt128" TargetId.solana TargetKind.solana
    wideI128Compiled "Int8/Int16/Int32/Int64 widths are supported"
  expectMaterializePlanInvariantV1 "WideInt128" TargetId.near TargetKind.near
    wideI128Compiled "Int8/Int16/Int32/Int64 integer types are supported"
  expectMaterializePlanInvariantV1 "WideInt128" TargetId.noir TargetKind.noir
    wideI128Compiled "Int8/Int16/Int32/Int64 integer widths are supported"
  expectMaterializePlanInvariantV1 "WideInt128" TargetId.aleo TargetKind.aleo
    wideI128Compiled "UInt64/UInt32/UInt16/UInt8/Int64 widths are supported"
  expectMaterializePlanInvariantV1 "WideInt128" TargetId.psy TargetKind.psy
    wideI128Compiled "UInt64/UInt32/UInt16/UInt8 and Int8/Int16/Int32/Int64"
  expectMaterializePlanInvariantV1 "WideInt128" TargetId.cosmwasm TargetKind.cosmwasm
    wideI128Compiled "Int128/256 fail closed"
  expectMaterializePlanInvariantV1 "WideInt128" TargetId.ton TargetKind.ton
    wideI128Compiled "Int128/256 fail closed"
  for (target, kind) in #[
      (TargetId.quint, TargetKind.quint),
      (TargetId.soroban, TargetKind.soroban),
      (TargetId.openvm, TargetKind.openvm),
      (TargetId.icp, TargetKind.icp)] do
    expectMaterializePlanInvariantV1 "WideInt128" target kind wideI128Compiled
      "only anonymous UInt64/Int64 widths are supported"

  -- WideInt256: Int256 state/return. Same twelve named-width FC needles
  -- as WideInt128, so Int256 stays closed even if Int128 later opens.
  -- Not opening Int128/256. WideInt128 / WideUInt / WideUInt256 stay.
  let wideInt256Source :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program WideInt256 where\n" ++
    "  state n : Int256\n\n" ++
    "  init(x : Int256) do\n" ++
    "    n := x\n\n" ++
    "  entry bump(d : Int256) : Int256 do\n" ++
    "    n := n + d\n" ++
    "    return n\n\n" ++
    "  view get() : Int256 do\n" ++
    "    return n\n\n" ++
    "end ProofForgeV2.Examples\n"
  let wideI256V1 ← match ← session.selectProgramV1 wideInt256Source
      "<targets-int256>" "Examples.WideInt256" none with
    | .ok v => pure v
    | .error e => throw <| IO.userError s!"WideInt256 select: {e.render}"
  let wideI256Compiled ← liftResult <| Compiler.compileValidatedSourceV1 wideI256V1
  expectMaterializePlanInvariantV1 "WideInt256" TargetId.evm TargetKind.evm
    wideI256Compiled "Int8/Int16/Int32/Int64 integer widths are supported"
  expectMaterializePlanInvariantV1 "WideInt256" TargetId.solana TargetKind.solana
    wideI256Compiled "Int8/Int16/Int32/Int64 widths are supported"
  expectMaterializePlanInvariantV1 "WideInt256" TargetId.near TargetKind.near
    wideI256Compiled "Int8/Int16/Int32/Int64 integer types are supported"
  expectMaterializePlanInvariantV1 "WideInt256" TargetId.noir TargetKind.noir
    wideI256Compiled "Int8/Int16/Int32/Int64 integer widths are supported"
  expectMaterializePlanInvariantV1 "WideInt256" TargetId.aleo TargetKind.aleo
    wideI256Compiled "UInt64/UInt32/UInt16/UInt8/Int64 widths are supported"
  expectMaterializePlanInvariantV1 "WideInt256" TargetId.psy TargetKind.psy
    wideI256Compiled "UInt64/UInt32/UInt16/UInt8 and Int8/Int16/Int32/Int64"
  expectMaterializePlanInvariantV1 "WideInt256" TargetId.cosmwasm TargetKind.cosmwasm
    wideI256Compiled "Int128/256 fail closed"
  expectMaterializePlanInvariantV1 "WideInt256" TargetId.ton TargetKind.ton
    wideI256Compiled "Int128/256 fail closed"
  for (target, kind) in #[
      (TargetId.quint, TargetKind.quint),
      (TargetId.soroban, TargetKind.soroban),
      (TargetId.openvm, TargetKind.openvm),
      (TargetId.icp, TargetKind.icp)] do
    expectMaterializePlanInvariantV1 "WideInt256" target kind wideI256Compiled
      "only anonymous UInt64/Int64 widths are supported"

  -- WideInt64: Int64 state/return. Opposite of WideInt128/256: all
  -- twelve targets admit files-nonempty (envelope-4 homogeneous Int64).
  -- Not opening Int8/16/32. WideInt128 / WideInt256 / WideUInt /
  -- WideUInt256 stay.
  let wideInt64Source :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program WideInt64 where\n" ++
    "  state n : Int64\n\n" ++
    "  init(x : Int64) do\n" ++
    "    n := x\n\n" ++
    "  entry bump(d : Int64) : Int64 do\n" ++
    "    n := n + d\n" ++
    "    return n\n\n" ++
    "  view get() : Int64 do\n" ++
    "    return n\n\n" ++
    "end ProofForgeV2.Examples\n"
  let wideI64V1 ← match ← session.selectProgramV1 wideInt64Source
      "<targets-int64>" "Examples.WideInt64" none with
    | .ok v => pure v
    | .error e => throw <| IO.userError s!"WideInt64 select: {e.render}"
  let wideI64Compiled ← liftResult <| Compiler.compileValidatedSourceV1 wideI64V1
  for target in [TargetId.evm, TargetId.solana, TargetId.near, TargetId.noir,
      TargetId.aleo, TargetId.psy, TargetId.cosmwasm, TargetId.ton,
      TargetId.icp, TargetId.quint, TargetId.soroban, TargetId.openvm] do
    let out ← liftResult <| materializeSelected target wideI64Compiled
    expect (!(MaterializedArtifactsV1.filesOf out).isEmpty)
      s!"WideInt64: {target} must materialize Int64"

  -- WideInt32: Int32 state/return. Eight targets admit files-nonempty
  -- (evm/solana/near/noir/psy/aleo/cw/ton). Envelope-4 stay on the width
  -- needle. Int32 ≠ Int64. Arr/Map/Opt of Int32 stay FC.
  -- WideInt64 / WideInt128 / WideInt256 / WideUInt stay.
  let wideInt32Source :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program WideInt32 where\n" ++
    "  state n : Int32\n\n" ++
    "  init(x : Int32) do\n" ++
    "    n := x\n\n" ++
    "  entry bump(d : Int32) : Int32 do\n" ++
    "    n := n + d\n" ++
    "    return n\n\n" ++
    "  view get() : Int32 do\n" ++
    "    return n\n\n" ++
    "end ProofForgeV2.Examples\n"
  let wideI32V1 ← match ← session.selectProgramV1 wideInt32Source
      "<targets-int32>" "Examples.WideInt32" none with
    | .ok v => pure v
    | .error e => throw <| IO.userError s!"WideInt32 select: {e.render}"
  let wideI32Compiled ← liftResult <| Compiler.compileValidatedSourceV1 wideI32V1
  for target in [TargetId.evm, TargetId.solana, TargetId.near, TargetId.noir,
      TargetId.psy, TargetId.aleo, TargetId.cosmwasm, TargetId.ton] do
    let out ← liftResult <| materializeSelected target wideI32Compiled
    expect (!(MaterializedArtifactsV1.filesOf out).isEmpty)
      s!"WideInt32: {target} must materialize Int32"
  for (target, kind) in #[
      (TargetId.quint, TargetKind.quint),
      (TargetId.soroban, TargetKind.soroban),
      (TargetId.openvm, TargetKind.openvm),
      (TargetId.icp, TargetKind.icp)] do
    expectMaterializePlanInvariantV1 "WideInt32" target kind wideI32Compiled
      "only anonymous UInt64/Int64 widths are supported"

  -- WideInt16: Int16 state/return. Same eight-admit / envelope-4-decline
  -- set as WideInt32, but Int16 ≠ Int32 so it is its own pin.
  -- WideInt32 / WideInt64 / WideInt128 / WideInt256 stay.
  let wideInt16Source :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program WideInt16 where\n" ++
    "  state n : Int16\n\n" ++
    "  init(x : Int16) do\n" ++
    "    n := x\n\n" ++
    "  entry bump(d : Int16) : Int16 do\n" ++
    "    n := n + d\n" ++
    "    return n\n\n" ++
    "  view get() : Int16 do\n" ++
    "    return n\n\n" ++
    "end ProofForgeV2.Examples\n"
  let wideI16V1 ← match ← session.selectProgramV1 wideInt16Source
      "<targets-int16>" "Examples.WideInt16" none with
    | .ok v => pure v
    | .error e => throw <| IO.userError s!"WideInt16 select: {e.render}"
  let wideI16Compiled ← liftResult <| Compiler.compileValidatedSourceV1 wideI16V1
  for target in [TargetId.evm, TargetId.solana, TargetId.near, TargetId.noir,
      TargetId.psy, TargetId.aleo, TargetId.cosmwasm, TargetId.ton] do
    let out ← liftResult <| materializeSelected target wideI16Compiled
    expect (!(MaterializedArtifactsV1.filesOf out).isEmpty)
      s!"WideInt16: {target} must materialize Int16"
  for (target, kind) in #[
      (TargetId.quint, TargetKind.quint),
      (TargetId.soroban, TargetKind.soroban),
      (TargetId.openvm, TargetKind.openvm),
      (TargetId.icp, TargetKind.icp)] do
    expectMaterializePlanInvariantV1 "WideInt16" target kind wideI16Compiled
      "only anonymous UInt64/Int64 widths are supported"

  -- WideInt8: Int8 state/return. Same eight-admit / envelope-4-decline set
  -- as WideInt16/32, but Int8 ≠ Int16 so it is its own pin (last narrow
  -- signed width). WideInt16 / WideInt32 / WideInt64 / WideInt128 /
  -- WideInt256 stay.
  let wideInt8Source :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program WideInt8 where\n" ++
    "  state n : Int8\n\n" ++
    "  init(x : Int8) do\n" ++
    "    n := x\n\n" ++
    "  entry bump(d : Int8) : Int8 do\n" ++
    "    n := n + d\n" ++
    "    return n\n\n" ++
    "  view get() : Int8 do\n" ++
    "    return n\n\n" ++
    "end ProofForgeV2.Examples\n"
  let wideI8V1 ← match ← session.selectProgramV1 wideInt8Source
      "<targets-int8>" "Examples.WideInt8" none with
    | .ok v => pure v
    | .error e => throw <| IO.userError s!"WideInt8 select: {e.render}"
  let wideI8Compiled ← liftResult <| Compiler.compileValidatedSourceV1 wideI8V1
  for target in [TargetId.evm, TargetId.solana, TargetId.near, TargetId.noir,
      TargetId.psy, TargetId.aleo, TargetId.cosmwasm, TargetId.ton] do
    let out ← liftResult <| materializeSelected target wideI8Compiled
    expect (!(MaterializedArtifactsV1.filesOf out).isEmpty)
      s!"WideInt8: {target} must materialize Int8"
  for (target, kind) in #[
      (TargetId.quint, TargetKind.quint),
      (TargetId.soroban, TargetKind.soroban),
      (TargetId.openvm, TargetKind.openvm),
      (TargetId.icp, TargetKind.icp)] do
    expectMaterializePlanInvariantV1 "WideInt8" target kind wideI8Compiled
      "only anonymous UInt64/Int64 widths are supported"

set_option maxRecDepth 10000 in
unsafe def runNamedAndArrayNeedles : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  -- N2c + B-3 PrincipalAddr + T10/T12 Principal storage pilot.
  -- Normalize admits identity-only Principal (state/params/eq/ne). Wire is
  -- variable-length u32-prefixed 1..4096 body. T10 opens EVM; T12 opens
  -- Solana/NEAR/Noir state/param leaf storage (len + 8×UInt64, ≤64B body)
  -- without Principal→address mapping. Psy PSY-SCALAR-ABI opens the same
  -- wire-identity layout as `len`+8×UInt32 (max 32B; not address). B-3 research
  -- pin still holds: storage is wire identity leaves, not pubkey/account-id/Field.
  let prinSource :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program PrincipalMix where\n" ++
    "  state owner : Principal\n\n" ++
    "  init(initial : Principal) do\n" ++
    "    owner := initial\n\n" ++
    "  entry set(who : Principal) : Bool do\n" ++
    "    owner := who\n" ++
    "    return true\n\n" ++
    "  entry eq(a : Principal, b : Principal) : Bool do\n" ++
    "    return a == b\n\n" ++
    "  entry matchesOwner(who : Principal) : Bool do\n" ++
    "    return owner == who\n\n" ++
    "end ProofForgeV2.Examples\n"
  let prinV1 ← match ← session.selectProgramV1 prinSource
      "<targets-n2c-principal>" "Examples.PrincipalMix" none with
    | .ok v => pure v
    | .error e => throw <| IO.userError s!"N2c principal select: {e.render}"
  let prinCompiled ← liftResult <| Compiler.compileValidatedSourceV1 prinV1
  -- T10: EVM admits Principal storage (9 leaf slots) and materializes.
  let prinEvm ← liftResult <| materializeSelected TargetId.evm prinCompiled
  let some prinYul := (MaterializedArtifactsV1.filesOf prinEvm).find?
      (·.path == "PrincipalMix.yul") |
    throw <| IO.userError "T10 principal: missing PrincipalMix.yul"
  -- Scalar Principal state still flattens to 9 leaves; loads go through the
  -- shared `pf_sload_u64` helper (not bare `sload(N)` in entry bodies).
  expect (
      (prinYul.contents.contains "pf_sload_u64(0)" &&
        prinYul.contents.contains "pf_sload_u64(8)") ||
      (prinYul.contents.contains "sload(0)" &&
        prinYul.contents.contains "sload(8)"))
    "T10 EVM Principal state must load all 9 leaf slots (0..8 via pf_sload_u64 or sload)"
  let prinPlan ← liftResult <| planEvm prinCompiled
  expect (prinPlan.storageLayout.size == 9)
    s!"T10 EVM Principal state must flatten to 9 leaves, got {prinPlan.storageLayout.size}"
  expect (prinPlan.storageLayout[0]!.name == "owner_len")
    s!"T10 Principal leaf 0 must be owner_len, got {prinPlan.storageLayout[0]!.name}"
  expect (prinPlan.storageLayout[1]!.name == "owner_w0")
    s!"T10 Principal leaf 1 must be owner_w0, got {prinPlan.storageLayout[1]!.name}"
  expect (prinPlan.storageLayout[8]!.name == "owner_w7")
    s!"T10 Principal leaf 8 must be owner_w7, got {prinPlan.storageLayout[8]!.name}"
  -- T12: Solana/NEAR/Noir admit Principal storage (9 leaf slots) and materialize.
  let prinSol ← liftResult <| materializeSelected TargetId.solana prinCompiled
  let prinNear ← liftResult <| materializeSelected TargetId.near prinCompiled
  let prinNoir ← liftResult <| materializeSelected TargetId.noir prinCompiled
  let solPlan ← liftResult <| planSolana prinCompiled
  expect (solPlan.stateAccount.fields.size == 9)
    s!"T12 Solana Principal state must flatten to 9 leaves, got {solPlan.stateAccount.fields.size}"
  expect (solPlan.stateAccount.fields[0]!.name == "owner_len")
    s!"T12 Solana Principal leaf 0 must be owner_len, got {solPlan.stateAccount.fields[0]!.name}"
  expect (solPlan.stateAccount.fields[8]!.name == "owner_w7")
    s!"T12 Solana Principal leaf 8 must be owner_w7, got {solPlan.stateAccount.fields[8]!.name}"
  let nearPlan ← liftResult <| planNear prinCompiled
  expect (nearPlan.storage.fields.size == 9)
    s!"T12 NEAR Principal state must flatten to 9 KV leaves, got {nearPlan.storage.fields.size}"
  expect (nearPlan.storage.fields[0]!.name == "owner_len")
    s!"T12 NEAR Principal leaf 0 must be owner_len, got {nearPlan.storage.fields[0]!.name}"
  expect (nearPlan.storage.fields[8]!.name == "owner_w7")
    s!"T12 NEAR Principal leaf 8 must be owner_w7, got {nearPlan.storage.fields[8]!.name}"
  let noirPlan ← liftResult <| planNoir prinCompiled
  expect (noirPlan.states.size == 9)
    s!"T12 Noir Principal state must flatten to 9 inputs, got {noirPlan.states.size}"
  expect (noirPlan.states[0]!.name == "owner_len")
    s!"T12 Noir Principal leaf 0 must be owner_len, got {noirPlan.states[0]!.name}"
  expect (noirPlan.states[8]!.name == "owner_w7")
    s!"T12 Noir Principal leaf 8 must be owner_w7, got {noirPlan.states[8]!.name}"
  -- Materialized artifacts must exist for the three newly-open targets.
  expect ((MaterializedArtifactsV1.filesOf prinSol).any
      (fun f => f.path.endsWith ".plan" || f.path.endsWith ".rs" ||
        f.path.endsWith ".s" || f.path.endsWith ".json"))
    "T12 Solana Principal materialize must emit plan/source artifacts"
  expect ((MaterializedArtifactsV1.filesOf prinNear).any
      (fun f => f.path.endsWith ".wat" || f.path.endsWith ".json"))
    "T12 NEAR Principal materialize must emit WAT/ABI artifacts"
  expect ((MaterializedArtifactsV1.filesOf prinNoir).any
      (fun f => f.path.endsWith ".nr" || f.path.endsWith ".json"))
    "T12 Noir Principal materialize must emit Noir source artifacts"
  -- PSY-SCALAR-ABI: Psy opens Principal wire-identity leaves (not address).
  let prinPsy ← liftResult <| materializeSelected TargetId.psy prinCompiled
  let prinPsyFiles := MaterializedArtifactsV1.filesOf prinPsy
  expect (prinPsyFiles.size == 1 && prinPsyFiles[0]!.path.endsWith ".dpn.json")
    "PSY-SCALAR-ABI Psy Principal materialize must emit exactly one DPN package"
  let psyPlan ← liftResult <| planPsy prinCompiled
  expect (psyPlan.stateFieldNames.size == 9)
    s!"PSY-SCALAR-ABI Psy Principal must flatten to 9 Felt leaves, got {psyPlan.stateFieldNames.size}"
  expect (psyPlan.stateFieldNames[0]! == "owner_len")
    s!"Psy Principal leaf 0 must be owner_len, got {psyPlan.stateFieldNames[0]!}"
  -- Extra seven from probe; CosmWasm admits identity storage (files nonempty).
  -- Aleo/TON/Quint/Soroban/ICP/OpenVM stay FC. Not opening Principal; not
  -- remapping Principal → pubkey / account-id / Field.
  let prinCw ← liftResult <| materializeSelected TargetId.cosmwasm prinCompiled
  expect (!(MaterializedArtifactsV1.filesOf prinCw).isEmpty)
    "N2c principal: CosmWasm must materialize Principal identity storage"
  for target in [TargetId.aleo, TargetId.quint, TargetId.ton, TargetId.soroban,
      TargetId.icp, TargetId.openvm] do
    match materializeSelected target prinCompiled with
    | .ok _ =>
        throw <| IO.userError s!"N2c principal: {target} must decline Principal"
    | .error e =>
        expect ((e.render).contains "Principal" ||
            (e.render).contains "unsupported" ||
            (e.render).contains "pilot" ||
            (e.render).contains "public" ||
            (e.render).contains "anonymous" ||
            (e.render).contains "identity")
          s!"N2c principal {target} message must cite Principal/identity boundary, got {e.render}"
  -- B-3 honesty pin survives T12: storage is wire identity leaves, not a
  -- 32-byte pubkey reinterpretation. Positive Solana materialize proves the
  -- leaf layout; wording still documents the non-match in Envelope diagnostics
  -- for unsupported Principal shapes (e.g. multi-word Principal return).
  -- T10: Principal multi-word entry *result* still fail closed (same gap as
  -- String return; storage/param/eq are open). Pins ResultKind surface.
  let prinRetSource :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program PrincipalReturn where\n" ++
    "  state owner : Principal\n\n" ++
    "  init(initial : Principal) do\n" ++
    "    owner := initial\n\n" ++
    "  view getOwner() : Principal do\n" ++
    "    return owner\n\n" ++
    "end ProofForgeV2.Examples\n"
  let prinRetV1 ← match ← session.selectProgramV1 prinRetSource
      "<targets-t10-principal-return>" "Examples.PrincipalReturn" none with
    | .ok v => pure v
    | .error e => throw <| IO.userError s!"T10 principal return select: {e.render}"
  let prinRetCompiled ← liftResult <| Compiler.compileValidatedSourceV1 prinRetV1
  match materializeSelected TargetId.evm prinRetCompiled with
  | .ok _ =>
      throw <| IO.userError
        "T10: EVM Principal entry/view result must remain fail closed (no multi-word ResultKind)"
  | .error e =>
      expect ((e.render).contains "Principal" ||
          (e.render).contains "return" ||
          (e.render).contains "UInt" ||
          (e.render).contains "unsupported" ||
          (e.render).contains "public")
        s!"T10 Principal return decline must cite result surface, got {e.render}"
  -- Extra eleven from probe; not opening Principal ResultKind / remap.
  for target in [TargetId.solana, TargetId.near, TargetId.noir, TargetId.aleo,
      TargetId.psy, TargetId.quint, TargetId.cosmwasm, TargetId.ton,
      TargetId.soroban, TargetId.icp, TargetId.openvm] do
    match materializeSelected target prinRetCompiled with
    | .ok _ =>
        throw <| IO.userError
          s!"T10: {target} Principal view result must remain fail closed"
    | .error e =>
        expect ((e.render).contains "Principal" ||
            (e.render).contains "return" ||
            (e.render).contains "UInt" ||
            (e.render).contains "unsupported" ||
            (e.render).contains "public" ||
            (e.render).contains "result" ||
            (e.render).contains "query")
          s!"T10 Principal return {target} must cite result surface, got {e.render}"

  -- N3 / NoirAggregate / H3 PsyAleoAggregate / L1 NearNamedAggregate / L2
  -- SolanaNamedAggregate: named Struct state + field assign product pin —
  -- all six targets admit (flatten-to-leaf).
  let structStateSource :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program PointBox where\n" ++
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
    "    return p.x\n\n" ++
    "end ProofForgeV2.Examples\n"
  let structV1 ← match ← session.selectProgramV1 structStateSource
      "<targets-n3-struct-state>" "Examples.PointBox" none with
    | .ok v => pure v
    | .error e => throw <| IO.userError s!"N3 struct-state select: {e.render}"
  let structCompiled ← liftResult <| Compiler.compileValidatedSourceV1 structV1
  let evmStruct ← liftResult <| planEvm structCompiled
  expect (evmStruct.storageLayout.size == 2)
    s!"N3 struct-state: EVM flattened leaf slots for Point.x/y, got {evmStruct.storageLayout.size}"
  expect (evmStruct.entries.any fun e => e.name == "setX")
    "N3 struct-state: EVM plan has setX entry"
  -- L2 SolanaNamedAggregate: Solana admits named Struct flatten-to-leaf.
  let solanaStruct ← liftResult <| planSolana structCompiled
  expect (solanaStruct.stateAccount.fields.size == 2)
    s!"N3 struct-state: Solana flattened leaf slots for Point.x/y, got {solanaStruct.stateAccount.fields.size}"
  expect (solanaStruct.stateAccount.fields.any fun f => f.name == "p_x")
    "N3 struct-state: Solana leaf name p_x"
  expect (solanaStruct.stateAccount.fields.any fun f => f.name == "p_y")
    "N3 struct-state: Solana leaf name p_y"
  expect (solanaStruct.entries.any fun e => e.name == "setX")
    "N3 struct-state: Solana plan has setX entry"
  let _ ← liftResult <| materializeSelected TargetId.solana structCompiled
  let noirStruct ← liftResult <| planNoir structCompiled
  expect (noirStruct.states.size == 2)
    s!"NoirAggregate: Noir flattened leaf public inputs for Point.x/y, got {noirStruct.states.size}"
  expect (noirStruct.states.any fun f => f.name == "p_x")
    "NoirAggregate: Noir leaf name p_x"
  expect (noirStruct.states.any fun f => f.name == "p_y")
    "NoirAggregate: Noir leaf name p_y"
  expect (noirStruct.relations.any fun r => r.name == "setX")
    "NoirAggregate: Noir plan has setX relation"
  let _ ← liftResult <| materializeSelected TargetId.noir structCompiled
  -- H3 PsyAleoAggregate: Psy + Aleo admit named Struct flatten-to-leaf.
  let psyStruct ← liftResult <| planPsy structCompiled
  expect (psyStruct.stateFieldNames == #["p_x", "p_y"])
    s!"H3 Psy named Struct must flatten to p_x/p_y, got {psyStruct.stateFieldNames}"
  let _ ← liftResult <| materializeSelected TargetId.psy structCompiled
  let aleoStruct ← liftResult <| planAleo structCompiled
  expect (aleoStruct.stateFieldNames == #["p_x", "p_y"])
    s!"H3 Aleo named Struct must flatten to p_x/p_y, got {aleoStruct.stateFieldNames}"
  let _ ← liftResult <| materializeSelected TargetId.aleo structCompiled
  -- L1 NearNamedAggregate: NEAR admits named Struct flatten-to-KV leaves.
  let nearStruct ← liftResult <| planNear structCompiled
  expect (nearStruct.storage.fields.map (·.name) == #["p_x", "p_y"])
    s!"NearNamedAggregate: NEAR flattened KV leaves p_x/p_y, got {nearStruct.storage.fields.map (·.name)}"
  expect (nearStruct.entries.any fun e => e.name == "setX")
    "NearNamedAggregate: NEAR plan has setX entry"
  let _ ← liftResult <| materializeSelected TargetId.near structCompiled
  -- Extra six from probe; CosmWasm/TON admit named Struct (files nonempty).
  -- Quint/Soroban/ICP/OpenVM stay envelope FC. Not opening named Struct.
  for target in [TargetId.cosmwasm, TargetId.ton] do
    let out ← liftResult <| materializeSelected target structCompiled
    expect (!(MaterializedArtifactsV1.filesOf out).isEmpty)
      s!"N3 struct-state: {target} must materialize named Struct"
  for target in [TargetId.quint, TargetId.soroban, TargetId.icp, TargetId.openvm] do
    match materializeSelected target structCompiled with
    | .ok _ =>
        throw <| IO.userError s!"N3 struct-state: {target} must decline named Struct"
    | .error e =>
        expect ((e.render).contains "Struct" ||
            (e.render).contains "named" ||
            (e.render).contains "unsupported" ||
            (e.render).contains "pilot" ||
            (e.render).contains "public" ||
            (e.render).contains "aggregate" ||
            (e.render).contains "anonymous")
          s!"N3 struct-state {target} message must cite named/aggregate boundary, got {e.render}"

  -- MaybeMark: named Enum state. Eight materializers admit; Quint/Soroban/
  -- ICP/OpenVM stay envelope FC. Not opening Enum on those four.
  -- State only — no Enum return ABI. Files-nonempty or named decline.
  let enumStateSource :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program MaybeMark where\n" ++
    "  enum Maybe where\n" ++
    "    | None\n" ++
    "    | Some(UInt64)\n" ++
    "  state m : Maybe\n\n" ++
    "  init() do\n" ++
    "    m := Maybe.None()\n\n" ++
    "  entry put(v : UInt64) : UInt64 do\n" ++
    "    m := Maybe.Some(v)\n" ++
    "    return v\n\n" ++
    "end ProofForgeV2.Examples\n"
  let enumV1 ← match ← session.selectProgramV1 enumStateSource
      "<targets-enum-state>" "Examples.MaybeMark" none with
    | .ok v => pure v
    | .error e => throw <| IO.userError s!"MaybeMark select: {e.render}"
  let enumCompiled ← liftResult <| Compiler.compileValidatedSourceV1 enumV1
  for target in [TargetId.evm, TargetId.solana, TargetId.near, TargetId.noir,
      TargetId.psy, TargetId.aleo, TargetId.cosmwasm, TargetId.ton] do
    let out ← liftResult <| materializeSelected target enumCompiled
    expect (!(MaterializedArtifactsV1.filesOf out).isEmpty)
      s!"MaybeMark: {target} must materialize named Enum"
  for target in [TargetId.quint, TargetId.soroban, TargetId.icp, TargetId.openvm] do
    match materializeSelected target enumCompiled with
    | .ok _ =>
        throw <| IO.userError s!"MaybeMark: {target} must decline named Enum"
    | .error e =>
        expect ((e.render).contains "named" ||
            (e.render).contains "Enum" ||
            (e.render).contains "unsupported" ||
            (e.render).contains "pilot" ||
            (e.render).contains "public")
          s!"MaybeMark {target} message must cite named/Enum boundary, got {e.render}"

  -- MaybeRetBox: named Enum *entry* return. Seven materializers admit.
  -- TON view-only B-RET FC; Quint/Soroban/OpenVM/ICP stay named-types
  -- UInt64-pilot FC. Entry peek, not view get (Aleo computed-view).
  -- Not opening Enum return on the decline set. MaybeMark state pin stays.
  let enumRetSource :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program MaybeRetBox where\n" ++
    "  enum Maybe where\n" ++
    "    | None\n" ++
    "    | Some(UInt64)\n" ++
    "  state m : Maybe\n\n" ++
    "  init() do\n" ++
    "    m := Maybe.None()\n\n" ++
    "  entry peek() : Maybe do\n" ++
    "    return m\n\n" ++
    "end ProofForgeV2.Examples\n"
  let enumRetV1 ← match ← session.selectProgramV1 enumRetSource
      "<targets-enum-ret>" "Examples.MaybeRetBox" none with
    | .ok v => pure v
    | .error e => throw <| IO.userError s!"MaybeRetBox select: {e.render}"
  let enumRetCompiled ← liftResult <| Compiler.compileValidatedSourceV1 enumRetV1
  for target in [TargetId.evm, TargetId.solana, TargetId.near, TargetId.noir,
      TargetId.aleo, TargetId.psy, TargetId.cosmwasm] do
    let out ← liftResult <| materializeSelected target enumRetCompiled
    expect (!(MaterializedArtifactsV1.filesOf out).isEmpty)
      s!"MaybeRetBox: {target} must materialize named Enum entry return"
  expectMaterializePlanInvariantV1 "MaybeRetBox" TargetId.ton TargetKind.ton
    enumRetCompiled "entry 'peek' cannot return multi-leaf aggregate"
  for (target, kind) in #[
      (TargetId.quint, TargetKind.quint),
      (TargetId.soroban, TargetKind.soroban),
      (TargetId.openvm, TargetKind.openvm),
      (TargetId.icp, TargetKind.icp)] do
    expectMaterializePlanInvariantV1 "MaybeRetBox" target kind enumRetCompiled
      "named types are outside the current UInt64 pilot"

  -- MaybeViewRet: named Enum *view* return. Distinct from MaybeRetBox
  -- entry: TON view-only B-RET admits; Aleo query-descriptor admit
  -- (`kind=computed`, not Final). Quint/Soroban/OpenVM/ICP stay
  -- named-types UInt64-pilot FC. MaybeMark / MaybeRetBox stay.
  let enumViewRetSource :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program MaybeViewRet where\n" ++
    "  enum Maybe where\n" ++
    "    | None\n" ++
    "    | Some(UInt64)\n" ++
    "  state m : Maybe\n\n" ++
    "  init() do\n" ++
    "    m := Maybe.None()\n\n" ++
    "  view peek() : Maybe do\n" ++
    "    return m\n\n" ++
    "end ProofForgeV2.Examples\n"
  let enumViewRetV1 ← match ← session.selectProgramV1 enumViewRetSource
      "<targets-enum-view-ret>" "Examples.MaybeViewRet" none with
    | .ok v => pure v
    | .error e => throw <| IO.userError s!"MaybeViewRet select: {e.render}"
  let enumViewRetCompiled ← liftResult <| Compiler.compileValidatedSourceV1 enumViewRetV1
  for target in [TargetId.evm, TargetId.solana, TargetId.near, TargetId.noir,
      TargetId.aleo, TargetId.psy, TargetId.cosmwasm, TargetId.ton] do
    let out ← liftResult <| materializeSelected target enumViewRetCompiled
    expect (!(MaterializedArtifactsV1.filesOf out).isEmpty)
      s!"MaybeViewRet: {target} must materialize named Enum view return"
  for (target, kind) in #[
      (TargetId.quint, TargetKind.quint),
      (TargetId.soroban, TargetKind.soroban),
      (TargetId.openvm, TargetKind.openvm),
      (TargetId.icp, TargetKind.icp)] do
    expectMaterializePlanInvariantV1 "MaybeViewRet" target kind enumViewRetCompiled
      "named types are outside the current UInt64 pilot"

  -- ArrayState: fixed Array UInt64 2 state — Solana + EVM + NEAR + Noir + H3
  -- Psy/Aleo admit (flatten to leaf slots named slots_0/slots_1; IndexGet/Set).
  -- Map UInt64→UInt64 dense pilot is open on EVM/Solana/NEAR/Noir (cap-8);
  -- EVM also admits Bytes (D4-E2) separately from this Array fixture.
  let arrayStateSource :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program ArrayBox where\n" ++
    "  state slots : Array UInt64 2\n\n" ++
    "  init() do\n" ++
    "    slots[0] := 0\n" ++
    "    slots[1] := 0\n\n" ++
    "  entry set0(v : UInt64) : UInt64 do\n" ++
    "    slots[0] := v\n" ++
    "    return slots[0]\n\n" ++
    "  view get0() : UInt64 do\n" ++
    "    return slots[0]\n\n" ++
    "end ProofForgeV2.Examples\n"
  let arrayV1 ← match ← session.selectProgramV1 arrayStateSource
      "<targets-array-state>" "Examples.ArrayBox" none with
    | .ok v => pure v
    | .error e => throw <| IO.userError s!"ArrayState select: {e.render}"
  let arrayCompiled ← liftResult <| Compiler.compileValidatedSourceV1 arrayV1
  let solanaArray ← liftResult <| planSolana arrayCompiled
  expect (solanaArray.stateAccount.fields.size == 2)
    s!"ArrayState: Solana flattened 2 leaf slots for Array UInt64 2, got {solanaArray.stateAccount.fields.size}"
  expect (solanaArray.stateAccount.fields.any fun f => f.name == "slots_0")
    "ArrayState: Solana leaf name slots_0"
  expect (solanaArray.stateAccount.fields.any fun f => f.name == "slots_1")
    "ArrayState: Solana leaf name slots_1"
  expect (solanaArray.entries.any fun e => e.name == "set0")
    "ArrayState: Solana plan has set0 entry"
  let evmArray ← liftResult <| planEvm arrayCompiled
  expect (evmArray.storageLayout.size == 2)
    s!"ArrayState: EVM flattened 2 storage slots for Array UInt64 2, got {evmArray.storageLayout.size}"
  expect (evmArray.storageLayout.any fun b => b.name == "slots_0" && b.slot == 0)
    "ArrayState: EVM leaf name slots_0 at slot 0"
  expect (evmArray.storageLayout.any fun b => b.name == "slots_1" && b.slot == 1)
    "ArrayState: EVM leaf name slots_1 at slot 1"
  expect (evmArray.entries.any fun e => e.name == "set0")
    "ArrayState: EVM plan has set0 entry"
  -- Product materialize path accepts EVM Array state.
  let _ ← liftResult <| materializeSelected TargetId.evm arrayCompiled
  -- H3 PsyAleoAggregate: Psy + Aleo admit Array UInt64 flatten-to-leaf.
  let psyArray ← liftResult <| planPsy arrayCompiled
  expect (psyArray.stateFieldNames == #["slots_0", "slots_1"])
    s!"H3 Psy Array must flatten to slots_0/slots_1, got {psyArray.stateFieldNames}"
  let _ ← liftResult <| materializeSelected TargetId.psy arrayCompiled
  let aleoArray ← liftResult <| planAleo arrayCompiled
  expect (aleoArray.stateFieldNames == #["slots_0", "slots_1"])
    s!"H3 Aleo Array must flatten to slots_0/slots_1, got {aleoArray.stateFieldNames}"
  let _ ← liftResult <| materializeSelected TargetId.aleo arrayCompiled
  -- NEAR ArrayState: same flatten-to-leaf as Solana (Map pilot shares ArrayMap policy).
  let nearArray ← liftResult <| planNear arrayCompiled
  expect (nearArray.storage.fields.size == 2)
    s!"ArrayState: NEAR flattened 2 leaf slots for Array UInt64 2, got {nearArray.storage.fields.size}"
  expect (nearArray.storage.fields.any fun f => f.name == "slots_0")
    "ArrayState: NEAR leaf name slots_0"
  expect (nearArray.storage.fields.any fun f => f.name == "slots_1")
    "ArrayState: NEAR leaf name slots_1"
  expect (nearArray.entries.any fun e => e.name == "set0")
    "ArrayState: NEAR plan has set0 entry"
  let _ ← liftResult <| materializeSelected TargetId.near arrayCompiled
  -- NoirContainer: Noir admits Array UInt64 flatten-to-leaf (same as Solana/NEAR/Psy/Aleo).
  let _ ← liftResult <| materializeSelected TargetId.noir arrayCompiled
  -- Extra six from probe; CosmWasm/TON/Quint/ICP/Soroban/OpenVM admit
  -- Array UInt64 2 (flatten to N scalar vars / instance keys / guest
  -- fields / i64 globals).
  for target in [TargetId.cosmwasm, TargetId.ton, TargetId.quint, TargetId.icp,
      TargetId.soroban, TargetId.openvm] do
    let out ← liftResult <| materializeSelected target arrayCompiled
    expect (!(MaterializedArtifactsV1.filesOf out).isEmpty)
      s!"ArrayState: {target} must materialize Array UInt64 2"

  -- ArrRetBox: Array UInt64 2 *entry* return. Seven materializers admit.
  -- TON view-only B-RET FC; Quint/Soroban/OpenVM/ICP stay Array-return FC.
  -- Entry peek, not view (TON view-only B-RET would conflate).
  -- Not opening Array return on the decline set. ArrayBox and ArrRetEntry
  -- Aleo pin stay.
  let arrRetSource :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program ArrRetBox where\n" ++
    "  state slots : Array UInt64 2\n\n" ++
    "  init() do\n" ++
    "    slots[0] := 0\n" ++
    "    slots[1] := 0\n\n" ++
    "  entry peek() : Array UInt64 2 do\n" ++
    "    return slots\n\n" ++
    "end ProofForgeV2.Examples\n"
  let arrRetV1 ← match ← session.selectProgramV1 arrRetSource
      "<targets-arr-ret>" "Examples.ArrRetBox" none with
    | .ok v => pure v
    | .error e => throw <| IO.userError s!"ArrRetBox select: {e.render}"
  let arrRetCompiled ← liftResult <| Compiler.compileValidatedSourceV1 arrRetV1
  for target in [TargetId.evm, TargetId.solana, TargetId.near, TargetId.noir,
      TargetId.aleo, TargetId.psy, TargetId.cosmwasm] do
    let out ← liftResult <| materializeSelected target arrRetCompiled
    expect (!(MaterializedArtifactsV1.filesOf out).isEmpty)
      s!"ArrRetBox: {target} must materialize Array UInt64 2 entry return"
  expectMaterializePlanInvariantV1 "ArrRetBox" TargetId.ton TargetKind.ton
    arrRetCompiled "entry 'peek' cannot return multi-leaf aggregate"
  expectMaterializePlanInvariantV1 "ArrRetBox" TargetId.quint TargetKind.quint
    arrRetCompiled "Array return is outside Q0"
  expectMaterializePlanInvariantV1 "ArrRetBox" TargetId.icp TargetKind.icp
    arrRetCompiled "Array return is outside ICP-2"
  expectMaterializePlanInvariantV1 "ArrRetBox" TargetId.soroban TargetKind.soroban
    arrRetCompiled "Array return is outside S0"
  expectMaterializePlanInvariantV1 "ArrRetBox" TargetId.openvm TargetKind.openvm
    arrRetCompiled "Array return is outside O0"

  -- ArrViewRet: Array UInt64 2 *view* return. Distinct from ArrRetBox
  -- entry: TON view-only B-RET admits; Aleo query-descriptor admit
  -- (`kind=computed`, not Final). Quint/Soroban/OpenVM/ICP stay
  -- Array-pilot FC. ArrRetBox / ArrRetEntry stay.
  let arrViewRetSource :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program ArrViewRet where\n" ++
    "  state slots : Array UInt64 2\n\n" ++
    "  init() do\n" ++
    "    slots[0] := 0\n" ++
    "    slots[1] := 0\n\n" ++
    "  view peek() : Array UInt64 2 do\n" ++
    "    return slots\n\n" ++
    "end ProofForgeV2.Examples\n"
  let arrViewRetV1 ← match ← session.selectProgramV1 arrViewRetSource
      "<targets-arr-view-ret>" "Examples.ArrViewRet" none with
    | .ok v => pure v
    | .error e => throw <| IO.userError s!"ArrViewRet select: {e.render}"
  let arrViewRetCompiled ← liftResult <| Compiler.compileValidatedSourceV1 arrViewRetV1
  for target in [TargetId.evm, TargetId.solana, TargetId.near, TargetId.noir,
      TargetId.aleo, TargetId.psy, TargetId.cosmwasm, TargetId.ton] do
    let out ← liftResult <| materializeSelected target arrViewRetCompiled
    expect (!(MaterializedArtifactsV1.filesOf out).isEmpty)
      s!"ArrViewRet: {target} must materialize Array UInt64 2 view return"
  expectMaterializePlanInvariantV1 "ArrViewRet" TargetId.quint TargetKind.quint
    arrViewRetCompiled "Array return is outside Q0"
  expectMaterializePlanInvariantV1 "ArrViewRet" TargetId.icp TargetKind.icp
    arrViewRetCompiled "Array return is outside ICP-2"
  expectMaterializePlanInvariantV1 "ArrViewRet" TargetId.soroban TargetKind.soroban
    arrViewRetCompiled "Array return is outside S0"
  expectMaterializePlanInvariantV1 "ArrViewRet" TargetId.openvm TargetKind.openvm
    arrViewRetCompiled "Array return is outside O0"

  -- NestArr: Array Array UInt64 2 2 state. All twelve targets stay named
  -- element/pilot FC. Not opening nested Array. ArrayBox / ArrRetBox /
  -- ArrViewRet stay.
  let nestArrSource :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program NestArr where\n" ++
    "  state slots : Array Array UInt64 2 2\n\n" ++
    "  init() do\n" ++
    "    slots[0][0] := 0\n\n" ++
    "  entry set00(v : UInt64) : UInt64 do\n" ++
    "    slots[0][0] := v\n" ++
    "    return v\n\n" ++
    "end ProofForgeV2.Examples\n"
  let nestArrV1 ← match ← session.selectProgramV1 nestArrSource
      "<targets-nest-arr>" "Examples.NestArr" none with
    | .ok v => pure v
    | .error e => throw <| IO.userError s!"NestArr select: {e.render}"
  let nestArrCompiled ← liftResult <| Compiler.compileValidatedSourceV1 nestArrV1
  expectMaterializePlanInvariantV1 "NestArr" TargetId.evm TargetKind.evm
    nestArrCompiled "Array state element must be UInt8/16/32/64"
  for (target, kind) in #[
      (TargetId.solana, TargetKind.solana),
      (TargetId.near, TargetKind.near),
      (TargetId.noir, TargetKind.noir),
      (TargetId.aleo, TargetKind.aleo),
      (TargetId.psy, TargetKind.psy),
      (TargetId.cosmwasm, TargetKind.cosmwasm),
      (TargetId.ton, TargetKind.ton)] do
    expectMaterializePlanInvariantV1 "NestArr" target kind nestArrCompiled
      "Array state element must be UInt64"
  expectMaterializePlanInvariantV1 "NestArr" TargetId.quint TargetKind.quint
    nestArrCompiled "Array element must be UInt64"
  expectMaterializePlanInvariantV1 "NestArr" TargetId.icp TargetKind.icp
    nestArrCompiled "Array element must be UInt64"
  expectMaterializePlanInvariantV1 "NestArr" TargetId.soroban TargetKind.soroban
    nestArrCompiled "Array element must be UInt64"
  expectMaterializePlanInvariantV1 "NestArr" TargetId.openvm TargetKind.openvm
    nestArrCompiled "Array element must be UInt64"

  -- ArrOpt: Array Option UInt64 2 state. All twelve targets stay named
  -- element/pilot FC. Not opening Array-of-Option. NestArr / ArrayBox /
  -- OptBox stay.
  let arrOptSource :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program ArrOpt where\n" ++
    "  state slots : Array Option UInt64 2\n\n" ++
    "  init() do\n" ++
    "    slots[0] := Option.none()\n" ++
    "    slots[1] := Option.none()\n\n" ++
    "  entry set0(v : UInt64) : UInt64 do\n" ++
    "    slots[0] := Option.some(v)\n" ++
    "    return v\n\n" ++
    "end ProofForgeV2.Examples\n"
  let arrOptV1 ← match ← session.selectProgramV1 arrOptSource
      "<targets-arr-opt>" "Examples.ArrOpt" none with
    | .ok v => pure v
    | .error e => throw <| IO.userError s!"ArrOpt select: {e.render}"
  let arrOptCompiled ← liftResult <| Compiler.compileValidatedSourceV1 arrOptV1
  expectMaterializePlanInvariantV1 "ArrOpt" TargetId.evm TargetKind.evm
    arrOptCompiled "Array state element must be UInt8/16/32/64"
  for (target, kind) in #[
      (TargetId.solana, TargetKind.solana),
      (TargetId.near, TargetKind.near),
      (TargetId.noir, TargetKind.noir),
      (TargetId.aleo, TargetKind.aleo),
      (TargetId.psy, TargetKind.psy),
      (TargetId.cosmwasm, TargetKind.cosmwasm),
      (TargetId.ton, TargetKind.ton)] do
    expectMaterializePlanInvariantV1 "ArrOpt" target kind arrOptCompiled
      "Array state element must be UInt64"
  -- Quint/Soroban/OpenVM admit Option type; Array-of-Option still fails
  -- on the Array element needle. ICP stays Option-pilot.
  for (target, kind) in #[
      (TargetId.quint, TargetKind.quint),
      (TargetId.soroban, TargetKind.soroban),
      (TargetId.openvm, TargetKind.openvm)] do
    expectMaterializePlanInvariantV1 "ArrOpt" target kind arrOptCompiled
      "Array element must be UInt64"
  expectMaterializePlanInvariantV1 "ArrOpt" TargetId.icp TargetKind.icp
    arrOptCompiled "anonymous Option is outside the current container-state pilot"

  -- ArrBytes: Array Bytes 4 2 state. All twelve targets stay named
  -- element/pilot FC. Not opening Array-of-Bytes. ArrOpt / ArrayBox /
  -- BytesBox stay.
  let arrBytesSource :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program ArrBytes where\n" ++
    "  state slots : Array Bytes 4 2\n\n" ++
    "  init() do\n" ++
    "    slots[0][0] := 0\n\n" ++
    "  entry set00(v : UInt64) : UInt64 do\n" ++
    "    slots[0][0] := 0\n" ++
    "    return v\n\n" ++
    "end ProofForgeV2.Examples\n"
  let arrBytesV1 ← match ← session.selectProgramV1 arrBytesSource
      "<targets-arr-bytes>" "Examples.ArrBytes" none with
    | .ok v => pure v
    | .error e => throw <| IO.userError s!"ArrBytes select: {e.render}"
  let arrBytesCompiled ← liftResult <| Compiler.compileValidatedSourceV1 arrBytesV1
  expectMaterializePlanInvariantV1 "ArrBytes" TargetId.evm TargetKind.evm
    arrBytesCompiled "Array state element must be UInt8/16/32/64"
  for (target, kind) in #[
      (TargetId.solana, TargetKind.solana),
      (TargetId.near, TargetKind.near),
      (TargetId.noir, TargetKind.noir),
      (TargetId.aleo, TargetKind.aleo),
      (TargetId.psy, TargetKind.psy),
      (TargetId.cosmwasm, TargetKind.cosmwasm),
      (TargetId.ton, TargetKind.ton)] do
    expectMaterializePlanInvariantV1 "ArrBytes" target kind arrBytesCompiled
      "Array state element must be UInt64"
  for (target, kind) in #[
      (TargetId.quint, TargetKind.quint),
      (TargetId.soroban, TargetKind.soroban),
      (TargetId.openvm, TargetKind.openvm),
      (TargetId.icp, TargetKind.icp)] do
    expectMaterializePlanInvariantV1 "ArrBytes" target kind arrBytesCompiled
      "anonymous Bytes is outside the current container-state pilot"

  -- ArrMap: Array Map UInt64 UInt64 2 state. All twelve targets stay named
  -- element/pilot FC. Not opening Array-of-Map. ArrBytes / ArrOpt /
  -- MapMini stay.
  let arrMapSource :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program ArrMap where\n" ++
    "  state slots : Array Map UInt64 UInt64 2\n\n" ++
    "  init() do\n" ++
    "    slots[0] := Map.empty()\n" ++
    "    slots[1] := Map.empty()\n\n" ++
    "  entry set0(v : UInt64) : UInt64 do\n" ++
    "    return v\n\n" ++
    "end ProofForgeV2.Examples\n"
  let arrMapV1 ← match ← session.selectProgramV1 arrMapSource
      "<targets-arr-map>" "Examples.ArrMap" none with
    | .ok v => pure v
    | .error e => throw <| IO.userError s!"ArrMap select: {e.render}"
  let arrMapCompiled ← liftResult <| Compiler.compileValidatedSourceV1 arrMapV1
  expectMaterializePlanInvariantV1 "ArrMap" TargetId.evm TargetKind.evm
    arrMapCompiled "Array state element must be UInt8/16/32/64"
  for (target, kind) in #[
      (TargetId.solana, TargetKind.solana),
      (TargetId.near, TargetKind.near),
      (TargetId.noir, TargetKind.noir),
      (TargetId.aleo, TargetKind.aleo),
      (TargetId.psy, TargetKind.psy),
      (TargetId.cosmwasm, TargetKind.cosmwasm),
      (TargetId.ton, TargetKind.ton)] do
    expectMaterializePlanInvariantV1 "ArrMap" target kind arrMapCompiled
      "Array state element must be UInt64"
  for (target, kind) in #[
      (TargetId.quint, TargetKind.quint),
      (TargetId.soroban, TargetKind.soroban),
      (TargetId.openvm, TargetKind.openvm)] do
    expectMaterializePlanInvariantV1 "ArrMap" target kind arrMapCompiled
      "Array element must be UInt64"
  expectMaterializePlanInvariantV1 "ArrMap" TargetId.icp TargetKind.icp
    arrMapCompiled "anonymous Map is outside the current container-state pilot"

  -- ArrPrin: Array Principal 2 state. Companion UInt64 `n` exists only so
  -- init/entry compile (no Principal literal; no bare return in init).
  -- All twelve stay named element/Principal FC. Not opening
  -- Array-of-Principal. ArrMap / ArrayBox / PrincipalMix stay.
  let arrPrinSource :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program ArrPrin where\n" ++
    "  state slots : Array Principal 2\n" ++
    "  state n : UInt64\n\n" ++
    "  init(x : UInt64) do\n" ++
    "    n := x\n\n" ++
    "  entry bump(d : UInt64) : UInt64 do\n" ++
    "    n := n + d\n" ++
    "    return n\n\n" ++
    "end ProofForgeV2.Examples\n"
  let arrPrinV1 ← match ← session.selectProgramV1 arrPrinSource
      "<targets-arr-prin>" "Examples.ArrPrin" none with
    | .ok v => pure v
    | .error e => throw <| IO.userError s!"ArrPrin select: {e.render}"
  let arrPrinCompiled ← liftResult <| Compiler.compileValidatedSourceV1 arrPrinV1
  expectMaterializePlanInvariantV1 "ArrPrin" TargetId.evm TargetKind.evm
    arrPrinCompiled "Array state element must be UInt8/16/32/64"
  for (target, kind) in #[
      (TargetId.solana, TargetKind.solana),
      (TargetId.near, TargetKind.near),
      (TargetId.noir, TargetKind.noir),
      (TargetId.psy, TargetKind.psy),
      (TargetId.cosmwasm, TargetKind.cosmwasm)] do
    expectMaterializePlanInvariantV1 "ArrPrin" target kind arrPrinCompiled
      "Array state element must be UInt64"
  expectMaterializePlanInvariantV1 "ArrPrin" TargetId.aleo TargetKind.aleo
    arrPrinCompiled "Principal/String stay fail-closed"
  expectMaterializePlanInvariantV1 "ArrPrin" TargetId.quint TargetKind.quint
    arrPrinCompiled "Array element must be UInt64"
  expectMaterializePlanInvariantV1 "ArrPrin" TargetId.ton TargetKind.ton
    arrPrinCompiled "no Field/Principal"
  for (target, kind) in #[
      (TargetId.soroban, TargetKind.soroban),
      (TargetId.openvm, TargetKind.openvm)] do
    expectMaterializePlanInvariantV1 "ArrPrin" target kind arrPrinCompiled
      "Principal/aggregates/Bytes"
  expectMaterializePlanInvariantV1 "ArrPrin" TargetId.icp TargetKind.icp
    arrPrinCompiled "Principal/aggregates/Map/Option/Bytes/String fail closed"

  -- ArrField: Array Field bn254_fr 2 state. Companion UInt64 `n` exists
  -- only so init/entry compile (no Field literal; no bare return in init).
  -- All twelve stay named element/Field FC. Not opening Array-of-Field.
  -- ArrPrin / ArrayBox / FieldMix / OptField stay.
  let arrFieldSource :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program ArrField where\n" ++
    "  state slots : Array Field bn254_fr 2\n" ++
    "  state n : UInt64\n\n" ++
    "  init(x : UInt64) do\n" ++
    "    n := x\n\n" ++
    "  entry bump(d : UInt64) : UInt64 do\n" ++
    "    n := n + d\n" ++
    "    return n\n\n" ++
    "end ProofForgeV2.Examples\n"
  let arrFieldV1 ← match ← session.selectProgramV1 arrFieldSource
      "<targets-arr-field>" "Examples.ArrField" none with
    | .ok v => pure v
    | .error e => throw <| IO.userError s!"ArrField select: {e.render}"
  let arrFieldCompiled ← liftResult <| Compiler.compileValidatedSourceV1 arrFieldV1
  expectMaterializePlanInvariantV1 "ArrField" TargetId.evm TargetKind.evm
    arrFieldCompiled "Array state element must be UInt8/16/32/64"
  for (target, kind) in #[
      (TargetId.solana, TargetKind.solana),
      (TargetId.near, TargetKind.near)] do
    expectMaterializePlanInvariantV1 "ArrField" target kind arrFieldCompiled
      "no native Field"
  expectMaterializePlanInvariantV1 "ArrField" TargetId.noir TargetKind.noir
    arrFieldCompiled "Array state element must be UInt64"
  expectMaterializePlanInvariantV1 "ArrField" TargetId.aleo TargetKind.aleo
    arrFieldCompiled "bn254 Fr and Goldilocks fail closed as wrong modulus"
  expectMaterializePlanInvariantV1 "ArrField" TargetId.psy TargetKind.psy
    arrFieldCompiled "bn254 Fr and BLS12-377 Fr fail closed as wrong modulus"
  expectMaterializePlanInvariantV1 "ArrField" TargetId.quint TargetKind.quint
    arrFieldCompiled "narrow Int/Field/aggregates/Bytes fail closed"
  expectMaterializePlanInvariantV1 "ArrField" TargetId.cosmwasm TargetKind.cosmwasm
    arrFieldCompiled "no Field"
  expectMaterializePlanInvariantV1 "ArrField" TargetId.ton TargetKind.ton
    arrFieldCompiled "no Field/Principal"
  for (target, kind) in #[
      (TargetId.soroban, TargetKind.soroban),
      (TargetId.openvm, TargetKind.openvm)] do
    expectMaterializePlanInvariantV1 "ArrField" target kind arrFieldCompiled
      "Int/Field/Principal/aggregates/Bytes"
  expectMaterializePlanInvariantV1 "ArrField" TargetId.icp TargetKind.icp
    arrFieldCompiled "Int/Field/Principal/aggregates/Map/Option/Bytes/String fail closed"

  -- ArrStr: Array String 2 state. Companion UInt64 `n` exists only so
  -- init/entry compile (no String literal; no bare return in init).
  -- All twelve stay named element/String FC. Not opening Array-of-String.
  -- ArrField / ArrayBox / StringInterfaceBoundary stay.
  let arrStrSource :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program ArrStr where\n" ++
    "  state slots : Array String 2\n" ++
    "  state n : UInt64\n\n" ++
    "  init(x : UInt64) do\n" ++
    "    n := x\n\n" ++
    "  entry bump(d : UInt64) : UInt64 do\n" ++
    "    n := n + d\n" ++
    "    return n\n\n" ++
    "end ProofForgeV2.Examples\n"
  let arrStrV1 ← match ← session.selectProgramV1 arrStrSource
      "<targets-arr-str>" "Examples.ArrStr" none with
    | .ok v => pure v
    | .error e => throw <| IO.userError s!"ArrStr select: {e.render}"
  let arrStrCompiled ← liftResult <| Compiler.compileValidatedSourceV1 arrStrV1
  expectMaterializePlanInvariantV1 "ArrStr" TargetId.evm TargetKind.evm
    arrStrCompiled "Array state element must be UInt8/16/32/64"
  expectMaterializePlanInvariantV1 "ArrStr" TargetId.solana TargetKind.solana
    arrStrCompiled "not a fixed 32-byte pubkey"
  expectMaterializePlanInvariantV1 "ArrStr" TargetId.near TargetKind.near
    arrStrCompiled "not a NEAR account-id string"
  expectMaterializePlanInvariantV1 "ArrStr" TargetId.noir TargetKind.noir
    arrStrCompiled "not a Field element"
  expectMaterializePlanInvariantV1 "ArrStr" TargetId.aleo TargetKind.aleo
    arrStrCompiled "Principal/String stay fail-closed"
  expectMaterializePlanInvariantV1 "ArrStr" TargetId.psy TargetKind.psy
    arrStrCompiled "Array state element must be UInt64"
  expectMaterializePlanInvariantV1 "ArrStr" TargetId.quint TargetKind.quint
    arrStrCompiled "narrow Int/Field/aggregates/Bytes fail closed"
  expectMaterializePlanInvariantV1 "ArrStr" TargetId.cosmwasm TargetKind.cosmwasm
    arrStrCompiled "no Field"
  expectMaterializePlanInvariantV1 "ArrStr" TargetId.ton TargetKind.ton
    arrStrCompiled "no Field/Principal"
  for (target, kind) in #[
      (TargetId.soroban, TargetKind.soroban),
      (TargetId.openvm, TargetKind.openvm)] do
    expectMaterializePlanInvariantV1 "ArrStr" target kind arrStrCompiled
      "Int/Field/Principal/aggregates/Bytes"
  expectMaterializePlanInvariantV1 "ArrStr" TargetId.icp TargetKind.icp
    arrStrCompiled "Map/Option/Bytes/String fail closed"

  -- ArrBool: Array Bool 2 state. All twelve stay named element/pilot FC.
  -- Not opening Array-of-Bool. ArrStr / ArrayBox / BoolPredicate stay.
  let arrBoolSource :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program ArrBool where\n" ++
    "  state slots : Array Bool 2\n\n" ++
    "  init() do\n" ++
    "    slots[0] := false\n" ++
    "    slots[1] := true\n\n" ++
    "  entry set0(v : UInt64) : UInt64 do\n" ++
    "    slots[0] := false\n" ++
    "    return v\n\n" ++
    "end ProofForgeV2.Examples\n"
  let arrBoolV1 ← match ← session.selectProgramV1 arrBoolSource
      "<targets-arr-bool>" "Examples.ArrBool" none with
    | .ok v => pure v
    | .error e => throw <| IO.userError s!"ArrBool select: {e.render}"
  let arrBoolCompiled ← liftResult <| Compiler.compileValidatedSourceV1 arrBoolV1
  expectMaterializePlanInvariantV1 "ArrBool" TargetId.evm TargetKind.evm
    arrBoolCompiled "Array state element must be UInt8/16/32/64"
  for (target, kind) in #[
      (TargetId.solana, TargetKind.solana),
      (TargetId.near, TargetKind.near),
      (TargetId.noir, TargetKind.noir),
      (TargetId.aleo, TargetKind.aleo),
      (TargetId.psy, TargetKind.psy),
      (TargetId.cosmwasm, TargetKind.cosmwasm),
      (TargetId.ton, TargetKind.ton)] do
    expectMaterializePlanInvariantV1 "ArrBool" target kind arrBoolCompiled
      "Array state element must be UInt64"
  expectMaterializePlanInvariantV1 "ArrBool" TargetId.quint TargetKind.quint
    arrBoolCompiled "Array element must be UInt64"
  expectMaterializePlanInvariantV1 "ArrBool" TargetId.icp TargetKind.icp
    arrBoolCompiled "Array element must be UInt64"
  expectMaterializePlanInvariantV1 "ArrBool" TargetId.soroban TargetKind.soroban
    arrBoolCompiled "Array element must be UInt64"
  expectMaterializePlanInvariantV1 "ArrBool" TargetId.openvm TargetKind.openvm
    arrBoolCompiled "Array element must be UInt64"

  -- ArrInt: Array Int64 2 state. EVM/Solana/NEAR/Noir/Aleo/Psy/CW admit
  -- signed leaves; TON admits int64 cells. Envelope-4 stay named FC on
  -- this mixed UInt64-param program. Not opening Array-of-Int8.
  let arrIntSource :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program ArrInt where\n" ++
    "  state slots : Array Int64 2\n\n" ++
    "  init() do\n" ++
    "    slots[0] := 0\n" ++
    "    slots[1] := 0\n\n" ++
    "  entry set0(v : UInt64) : UInt64 do\n" ++
    "    slots[0] := 0\n" ++
    "    return v\n\n" ++
    "end ProofForgeV2.Examples\n"
  let arrIntV1 ← match ← session.selectProgramV1 arrIntSource
      "<targets-arr-int>" "Examples.ArrInt" none with
    | .ok v => pure v
    | .error e => throw <| IO.userError s!"ArrInt select: {e.render}"
  let arrIntCompiled ← liftResult <| Compiler.compileValidatedSourceV1 arrIntV1
  let arrIntEvmOut ← liftResult <| materializeSelected TargetId.evm arrIntCompiled
  expect (!(MaterializedArtifactsV1.filesOf arrIntEvmOut).isEmpty)
    "ArrInt: evm must materialize Array Int64 2"
  let arrIntOut ← liftResult <| materializeSelected TargetId.cosmwasm arrIntCompiled
  expect (!(MaterializedArtifactsV1.filesOf arrIntOut).isEmpty)
    "ArrInt: cosmwasm must materialize Array Int64 2"
  let arrIntTonOut ← liftResult <| materializeSelected TargetId.ton arrIntCompiled
  expect (!(MaterializedArtifactsV1.filesOf arrIntTonOut).isEmpty)
    "ArrInt: ton must materialize Array Int64 2"
  let arrIntNearOut ← liftResult <| materializeSelected TargetId.near arrIntCompiled
  expect (!(MaterializedArtifactsV1.filesOf arrIntNearOut).isEmpty)
    "ArrInt: near must materialize Array Int64 2"
  let arrIntSolOut ← liftResult <| materializeSelected TargetId.solana arrIntCompiled
  expect (!(MaterializedArtifactsV1.filesOf arrIntSolOut).isEmpty)
    "ArrInt: solana must materialize Array Int64 2"
  let arrIntNoirOut ← liftResult <| materializeSelected TargetId.noir arrIntCompiled
  expect (!(MaterializedArtifactsV1.filesOf arrIntNoirOut).isEmpty)
    "ArrInt: noir must materialize Array Int64 2"
  let arrIntAleoOut ← liftResult <| materializeSelected TargetId.aleo arrIntCompiled
  expect (!(MaterializedArtifactsV1.filesOf arrIntAleoOut).isEmpty)
    "ArrInt: aleo must materialize Array Int64 2"
  let arrIntPsyOut ← liftResult <| materializeSelected TargetId.psy arrIntCompiled
  expect (!(MaterializedArtifactsV1.filesOf arrIntPsyOut).isEmpty)
    "ArrInt: psy must materialize Array Int64 2"
  expectMaterializePlanInvariantV1 "ArrInt" TargetId.quint TargetKind.quint
    arrIntCompiled "Array element must be UInt64"
  expectMaterializePlanInvariantV1 "ArrInt" TargetId.icp TargetKind.icp
    arrIntCompiled "Array element must be UInt64"
  expectMaterializePlanInvariantV1 "ArrInt" TargetId.soroban TargetKind.soroban
    arrIntCompiled "Array element must be UInt64"
  expectMaterializePlanInvariantV1 "ArrInt" TargetId.openvm TargetKind.openvm
    arrIntCompiled "Array element must be UInt64"

  -- ArrU128: Array UInt128 2 state. EVM+TON files-nonempty admit
  -- (TON = N consecutive uint128 c4 cells, not CosmWasm 2-limb).
  -- WideUInt admits bare UInt128 on eight targets (incl. Aleo/TON);
  -- Array-of-UInt128 admits EVM + TON only. Other ten stay named FC.
  -- ArrInt / ArrBool / WideUInt / WideInt8 stay.
  let arrU128Source :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program ArrU128 where\n" ++
    "  state slots : Array UInt128 2\n\n" ++
    "  init() do\n" ++
    "    slots[0] := 0\n" ++
    "    slots[1] := 0\n\n" ++
    "  entry set0(v : UInt64) : UInt64 do\n" ++
    "    slots[0] := 0\n" ++
    "    return v\n\n" ++
    "end ProofForgeV2.Examples\n"
  let arrU128V1 ← match ← session.selectProgramV1 arrU128Source
      "<targets-arr-u128>" "Examples.ArrU128" none with
    | .ok v => pure v
    | .error e => throw <| IO.userError s!"ArrU128 select: {e.render}"
  let arrU128Compiled ← liftResult <| Compiler.compileValidatedSourceV1 arrU128V1
  let arrU128Out ← liftResult <| materializeSelected TargetId.evm arrU128Compiled
  expect (!(MaterializedArtifactsV1.filesOf arrU128Out).isEmpty)
    "ArrU128: evm must materialize Array UInt128 2"
  let arrU128TonOut ← liftResult <| materializeSelected TargetId.ton arrU128Compiled
  expect (!(MaterializedArtifactsV1.filesOf arrU128TonOut).isEmpty)
    "ArrU128: ton must materialize Array UInt128 2"
  for (target, kind) in #[
      (TargetId.solana, TargetKind.solana),
      (TargetId.near, TargetKind.near),
      (TargetId.noir, TargetKind.noir),
      (TargetId.psy, TargetKind.psy),
      (TargetId.cosmwasm, TargetKind.cosmwasm),
      (TargetId.aleo, TargetKind.aleo)] do
    expectMaterializePlanInvariantV1 "ArrU128" target kind arrU128Compiled
      "Array state element must be UInt64"
  for (target, kind) in #[
      (TargetId.quint, TargetKind.quint),
      (TargetId.soroban, TargetKind.soroban),
      (TargetId.openvm, TargetKind.openvm),
      (TargetId.icp, TargetKind.icp)] do
    expectMaterializePlanInvariantV1 "ArrU128" target kind arrU128Compiled
      "only anonymous UInt64/Int64 widths are supported"

  -- ArrU256: Array UInt256 2 state. EVM-only files-nonempty admit.
  -- ArrU128 is EVM+TON; TON still fail-closes Array UInt256 on the
  -- Array-U64-element needle (contains-match). UInt256 ≠ UInt128 so
  -- this stays its own pin. WideUInt256 admits bare UInt256 on seven
  -- targets. Not opening Array-of-UInt256 on the eleven.
  -- ArrU128 / ArrInt / ArrBool / WideUInt256 stay.
  let arrU256Source :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program ArrU256 where\n" ++
    "  state slots : Array UInt256 2\n\n" ++
    "  init() do\n" ++
    "    slots[0] := 0\n" ++
    "    slots[1] := 0\n\n" ++
    "  entry set0(v : UInt64) : UInt64 do\n" ++
    "    slots[0] := 0\n" ++
    "    return v\n\n" ++
    "end ProofForgeV2.Examples\n"
  let arrU256V1 ← match ← session.selectProgramV1 arrU256Source
      "<targets-arr-u256>" "Examples.ArrU256" none with
    | .ok v => pure v
    | .error e => throw <| IO.userError s!"ArrU256 select: {e.render}"
  let arrU256Compiled ← liftResult <| Compiler.compileValidatedSourceV1 arrU256V1
  let arrU256Out ← liftResult <| materializeSelected TargetId.evm arrU256Compiled
  expect (!(MaterializedArtifactsV1.filesOf arrU256Out).isEmpty)
    "ArrU256: evm must materialize Array UInt256 2"
  for (target, kind) in #[
      (TargetId.solana, TargetKind.solana),
      (TargetId.near, TargetKind.near),
      (TargetId.noir, TargetKind.noir),
      (TargetId.psy, TargetKind.psy),
      (TargetId.cosmwasm, TargetKind.cosmwasm)] do
    expectMaterializePlanInvariantV1 "ArrU256" target kind arrU256Compiled
      "Array state element must be UInt64"
  expectMaterializePlanInvariantV1 "ArrU256" TargetId.aleo TargetKind.aleo
    arrU256Compiled "only anonymous UInt64/UInt32/UInt16/UInt8/UInt128/Int64/Int32/Int16/Int8 widths are supported"
  expectMaterializePlanInvariantV1 "ArrU256" TargetId.ton TargetKind.ton
    arrU256Compiled "Array state element must be UInt64"
  for (target, kind) in #[
      (TargetId.quint, TargetKind.quint),
      (TargetId.soroban, TargetKind.soroban),
      (TargetId.openvm, TargetKind.openvm),
      (TargetId.icp, TargetKind.icp)] do
    expectMaterializePlanInvariantV1 "ArrU256" target kind arrU256Compiled
      "only anonymous UInt64/Int64 widths are supported"

  -- ArrU32: Array UInt32 2 state. EVM-only files-nonempty admit. UInt32
  -- is a legal Aleo/TON width, so those two stay on Array-U64-element,
  -- not ArrU128's width needles. Quint/Soroban/OpenVM/ICP fail on the
  -- width needle first, not ArrBool's Array-pilot. Not opening
  -- Array-of-UInt32 on the eleven. ArrU128 / ArrU256 / ArrInt /
  -- MapU16Key stay.
  let arrU32Source :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program ArrU32 where\n" ++
    "  state slots : Array UInt32 2\n\n" ++
    "  init() do\n" ++
    "    slots[0] := 0\n" ++
    "    slots[1] := 0\n\n" ++
    "  entry set0(v : UInt64) : UInt64 do\n" ++
    "    slots[0] := 0\n" ++
    "    return v\n\n" ++
    "end ProofForgeV2.Examples\n"
  let arrU32V1 ← match ← session.selectProgramV1 arrU32Source
      "<targets-arr-u32>" "Examples.ArrU32" none with
    | .ok v => pure v
    | .error e => throw <| IO.userError s!"ArrU32 select: {e.render}"
  let arrU32Compiled ← liftResult <| Compiler.compileValidatedSourceV1 arrU32V1
  let arrU32Out ← liftResult <| materializeSelected TargetId.evm arrU32Compiled
  expect (!(MaterializedArtifactsV1.filesOf arrU32Out).isEmpty)
    "ArrU32: evm must materialize Array UInt32 2"
  for (target, kind) in #[
      (TargetId.solana, TargetKind.solana),
      (TargetId.near, TargetKind.near),
      (TargetId.noir, TargetKind.noir),
      (TargetId.aleo, TargetKind.aleo),
      (TargetId.psy, TargetKind.psy),
      (TargetId.cosmwasm, TargetKind.cosmwasm),
      (TargetId.ton, TargetKind.ton)] do
    expectMaterializePlanInvariantV1 "ArrU32" target kind arrU32Compiled
      "Array state element must be UInt64"
  expectMaterializePlanInvariantV1 "ArrU32" TargetId.quint TargetKind.quint
    arrU32Compiled "Array element must be UInt64"
  expectMaterializePlanInvariantV1 "ArrU32" TargetId.icp TargetKind.icp
    arrU32Compiled "Array element must be UInt64"
  expectMaterializePlanInvariantV1 "ArrU32" TargetId.soroban TargetKind.soroban
    arrU32Compiled "Array element must be UInt64"
  expectMaterializePlanInvariantV1 "ArrU32" TargetId.openvm TargetKind.openvm
    arrU32Compiled "Array element must be UInt64"

  -- ArrU16: Array UInt16 2 state. Same EVM-only admit / eleven-decline
  -- set as ArrU32, but UInt16 ≠ UInt32 so it is its own pin. Aleo/TON
  -- stay on Array-U64-element (legal width), not ArrU128's width
  -- needles. Quint/Soroban/OpenVM/ICP fail on the width needle first,
  -- not ArrBool's Array-pilot. Not opening Array-of-UInt16 on the
  -- eleven. ArrU32 / ArrU128 / ArrU256 / ArrInt stay.
  let arrU16Source :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program ArrU16 where\n" ++
    "  state slots : Array UInt16 2\n\n" ++
    "  init() do\n" ++
    "    slots[0] := 0\n" ++
    "    slots[1] := 0\n\n" ++
    "  entry set0(v : UInt64) : UInt64 do\n" ++
    "    slots[0] := 0\n" ++
    "    return v\n\n" ++
    "end ProofForgeV2.Examples\n"
  let arrU16V1 ← match ← session.selectProgramV1 arrU16Source
      "<targets-arr-u16>" "Examples.ArrU16" none with
    | .ok v => pure v
    | .error e => throw <| IO.userError s!"ArrU16 select: {e.render}"
  let arrU16Compiled ← liftResult <| Compiler.compileValidatedSourceV1 arrU16V1
  let arrU16Out ← liftResult <| materializeSelected TargetId.evm arrU16Compiled
  expect (!(MaterializedArtifactsV1.filesOf arrU16Out).isEmpty)
    "ArrU16: evm must materialize Array UInt16 2"
  for (target, kind) in #[
      (TargetId.solana, TargetKind.solana),
      (TargetId.near, TargetKind.near),
      (TargetId.noir, TargetKind.noir),
      (TargetId.aleo, TargetKind.aleo),
      (TargetId.psy, TargetKind.psy),
      (TargetId.cosmwasm, TargetKind.cosmwasm),
      (TargetId.ton, TargetKind.ton)] do
    expectMaterializePlanInvariantV1 "ArrU16" target kind arrU16Compiled
      "Array state element must be UInt64"
  for (target, kind) in #[
      (TargetId.quint, TargetKind.quint),
      (TargetId.soroban, TargetKind.soroban),
      (TargetId.openvm, TargetKind.openvm),
      (TargetId.icp, TargetKind.icp)] do
    expectMaterializePlanInvariantV1 "ArrU16" target kind arrU16Compiled
      "only anonymous UInt64/Int64 widths are supported"

  -- ArrU8: Array UInt8 2 state. Same EVM-only admit / eleven-decline
  -- set as ArrU16, but UInt8 ≠ UInt16 so it is its own pin (last
  -- narrow unsigned array width). Aleo/TON stay on Array-U64-element
  -- (legal width). Quint/Soroban/OpenVM/ICP fail on the width needle
  -- first, not ArrBool's Array-pilot. Not opening Array-of-UInt8 on
  -- the eleven. ArrU16 / ArrU32 / ArrU128 / ArrU256 stay.
  let arrU8Source :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program ArrU8 where\n" ++
    "  state slots : Array UInt8 2\n\n" ++
    "  init() do\n" ++
    "    slots[0] := 0\n" ++
    "    slots[1] := 0\n\n" ++
    "  entry set0(v : UInt64) : UInt64 do\n" ++
    "    slots[0] := 0\n" ++
    "    return v\n\n" ++
    "end ProofForgeV2.Examples\n"
  let arrU8V1 ← match ← session.selectProgramV1 arrU8Source
      "<targets-arr-u8>" "Examples.ArrU8" none with
    | .ok v => pure v
    | .error e => throw <| IO.userError s!"ArrU8 select: {e.render}"
  let arrU8Compiled ← liftResult <| Compiler.compileValidatedSourceV1 arrU8V1
  let arrU8Out ← liftResult <| materializeSelected TargetId.evm arrU8Compiled
  expect (!(MaterializedArtifactsV1.filesOf arrU8Out).isEmpty)
    "ArrU8: evm must materialize Array UInt8 2"
  for (target, kind) in #[
      (TargetId.solana, TargetKind.solana),
      (TargetId.near, TargetKind.near),
      (TargetId.noir, TargetKind.noir),
      (TargetId.aleo, TargetKind.aleo),
      (TargetId.psy, TargetKind.psy),
      (TargetId.cosmwasm, TargetKind.cosmwasm),
      (TargetId.ton, TargetKind.ton)] do
    expectMaterializePlanInvariantV1 "ArrU8" target kind arrU8Compiled
      "Array state element must be UInt64"
  for (target, kind) in #[
      (TargetId.quint, TargetKind.quint),
      (TargetId.soroban, TargetKind.soroban),
      (TargetId.openvm, TargetKind.openvm),
      (TargetId.icp, TargetKind.icp)] do
    expectMaterializePlanInvariantV1 "ArrU8" target kind arrU8Compiled
      "only anonymous UInt64/Int64 widths are supported"

set_option maxRecDepth 10000 in
unsafe def runSignedContainerNeedles : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  -- ArrI32: Array Int32 2 state. All twelve stay named FC. EVM declines
  -- signed arrays (ArrU32 EVM admits UInt32). Aleo/CW/TON fail on
  -- width / narrow-Int first, not ArrInt's Array-element. Int32 ≠
  -- Int64 and ≠ UInt32. Not opening Array-of-Int32. ArrU8 / ArrU32 /
  -- ArrInt / WideInt32 stay.
  let arrI32Source :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program ArrI32 where\n" ++
    "  state slots : Array Int32 2\n\n" ++
    "  init() do\n" ++
    "    slots[0] := 0\n" ++
    "    slots[1] := 0\n\n" ++
    "  entry set0(v : UInt64) : UInt64 do\n" ++
    "    slots[0] := 0\n" ++
    "    return v\n\n" ++
    "end ProofForgeV2.Examples\n"
  let arrI32V1 ← match ← session.selectProgramV1 arrI32Source
      "<targets-arr-i32>" "Examples.ArrI32" none with
    | .ok v => pure v
    | .error e => throw <| IO.userError s!"ArrI32 select: {e.render}"
  let arrI32Compiled ← liftResult <| Compiler.compileValidatedSourceV1 arrI32V1
  expectMaterializePlanInvariantV1 "ArrI32" TargetId.evm TargetKind.evm
    arrI32Compiled "Array state element must be UInt8/16/32/64"
  for (target, kind) in #[
      (TargetId.solana, TargetKind.solana),
      (TargetId.near, TargetKind.near),
      (TargetId.noir, TargetKind.noir),
      (TargetId.psy, TargetKind.psy),
      (TargetId.aleo, TargetKind.aleo)] do
    expectMaterializePlanInvariantV1 "ArrI32" target kind arrI32Compiled
      "Array state element must be UInt64"
  expectMaterializePlanInvariantV1 "ArrI32" TargetId.cosmwasm TargetKind.cosmwasm
    arrI32Compiled "Array state element must be UInt64"
  expectMaterializePlanInvariantV1 "ArrI32" TargetId.ton TargetKind.ton
    arrI32Compiled "Array state element must be UInt64"
  for (target, kind) in #[
      (TargetId.quint, TargetKind.quint),
      (TargetId.soroban, TargetKind.soroban),
      (TargetId.openvm, TargetKind.openvm),
      (TargetId.icp, TargetKind.icp)] do
    expectMaterializePlanInvariantV1 "ArrI32" target kind arrI32Compiled
      "only anonymous UInt64/Int64 widths are supported"

  -- ArrI16: Array Int16 2 state. Same twelve named-FC needles as
  -- ArrI32, but Int16 ≠ Int32 so it is its own pin. EVM declines
  -- signed arrays (ArrU16 EVM admits UInt16). Aleo/CW/TON stay on
  -- width / narrow-Int, not ArrInt's Array-element. Not opening
  -- Array-of-Int16. ArrI32 / ArrU16 / ArrInt / OptI32 stay.
  let arrI16Source :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program ArrI16 where\n" ++
    "  state slots : Array Int16 2\n\n" ++
    "  init() do\n" ++
    "    slots[0] := 0\n" ++
    "    slots[1] := 0\n\n" ++
    "  entry set0(v : UInt64) : UInt64 do\n" ++
    "    slots[0] := 0\n" ++
    "    return v\n\n" ++
    "end ProofForgeV2.Examples\n"
  let arrI16V1 ← match ← session.selectProgramV1 arrI16Source
      "<targets-arr-i16>" "Examples.ArrI16" none with
    | .ok v => pure v
    | .error e => throw <| IO.userError s!"ArrI16 select: {e.render}"
  let arrI16Compiled ← liftResult <| Compiler.compileValidatedSourceV1 arrI16V1
  expectMaterializePlanInvariantV1 "ArrI16" TargetId.evm TargetKind.evm
    arrI16Compiled "Array state element must be UInt8/16/32/64"
  for (target, kind) in #[
      (TargetId.solana, TargetKind.solana),
      (TargetId.near, TargetKind.near),
      (TargetId.noir, TargetKind.noir),
      (TargetId.psy, TargetKind.psy),
      (TargetId.aleo, TargetKind.aleo)] do
    expectMaterializePlanInvariantV1 "ArrI16" target kind arrI16Compiled
      "Array state element must be UInt64"
  expectMaterializePlanInvariantV1 "ArrI16" TargetId.cosmwasm TargetKind.cosmwasm
    arrI16Compiled "Array state element must be UInt64"
  expectMaterializePlanInvariantV1 "ArrI16" TargetId.ton TargetKind.ton
    arrI16Compiled "Array state element must be UInt64"
  for (target, kind) in #[
      (TargetId.quint, TargetKind.quint),
      (TargetId.soroban, TargetKind.soroban),
      (TargetId.openvm, TargetKind.openvm),
      (TargetId.icp, TargetKind.icp)] do
    expectMaterializePlanInvariantV1 "ArrI16" target kind arrI16Compiled
      "only anonymous UInt64/Int64 widths are supported"

  -- ArrI8: Array Int8 2 state. Same twelve named-FC needles as ArrI16,
  -- but Int8 ≠ Int16 so it is its own pin (last narrow signed array
  -- width). EVM declines signed arrays (ArrU8 EVM admits UInt8). Not
  -- opening Array-of-Int8. ArrI16 / ArrI32 / ArrU8 / ArrInt stay.
  let arrI8Source :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program ArrI8 where\n" ++
    "  state slots : Array Int8 2\n\n" ++
    "  init() do\n" ++
    "    slots[0] := 0\n" ++
    "    slots[1] := 0\n\n" ++
    "  entry set0(v : UInt64) : UInt64 do\n" ++
    "    slots[0] := 0\n" ++
    "    return v\n\n" ++
    "end ProofForgeV2.Examples\n"
  let arrI8V1 ← match ← session.selectProgramV1 arrI8Source
      "<targets-arr-i8>" "Examples.ArrI8" none with
    | .ok v => pure v
    | .error e => throw <| IO.userError s!"ArrI8 select: {e.render}"
  let arrI8Compiled ← liftResult <| Compiler.compileValidatedSourceV1 arrI8V1
  expectMaterializePlanInvariantV1 "ArrI8" TargetId.evm TargetKind.evm
    arrI8Compiled "Array state element must be UInt8/16/32/64"
  for (target, kind) in #[
      (TargetId.solana, TargetKind.solana),
      (TargetId.near, TargetKind.near),
      (TargetId.noir, TargetKind.noir),
      (TargetId.psy, TargetKind.psy),
      (TargetId.aleo, TargetKind.aleo)] do
    expectMaterializePlanInvariantV1 "ArrI8" target kind arrI8Compiled
      "Array state element must be UInt64"
  expectMaterializePlanInvariantV1 "ArrI8" TargetId.cosmwasm TargetKind.cosmwasm
    arrI8Compiled "Array state element must be UInt64"
  expectMaterializePlanInvariantV1 "ArrI8" TargetId.ton TargetKind.ton
    arrI8Compiled "Array state element must be UInt64"
  for (target, kind) in #[
      (TargetId.quint, TargetKind.quint),
      (TargetId.soroban, TargetKind.soroban),
      (TargetId.openvm, TargetKind.openvm),
      (TargetId.icp, TargetKind.icp)] do
    expectMaterializePlanInvariantV1 "ArrI8" target kind arrI8Compiled
      "only anonymous UInt64/Int64 widths are supported"

  -- MapMini: Map UInt64 UInt64 state. Eleven materializers admit
  -- (envelope Quint/Soroban/OpenVM flatten is 24 occ/key/val leaves).
  -- ICP stays Map-pilot (no Candid map). No Plan-shape pins.
  let mapMiniSource :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program MapMini where\n" ++
    "  state m : Map UInt64 UInt64\n\n" ++
    "  init() do\n" ++
    "    m := Map.empty()\n\n" ++
    "  entry put(k : UInt64, v : UInt64) : UInt64 do\n" ++
    "    m[k] := v\n" ++
    "    return v\n\n" ++
    "end ProofForgeV2.Examples\n"
  let mapV1 ← match ← session.selectProgramV1 mapMiniSource
      "<targets-map-mini>" "Examples.MapMini" none with
    | .ok v => pure v
    | .error e => throw <| IO.userError s!"MapMini select: {e.render}"
  let mapCompiled ← liftResult <| Compiler.compileValidatedSourceV1 mapV1
  for target in [TargetId.evm, TargetId.solana, TargetId.near, TargetId.noir,
      TargetId.psy, TargetId.aleo, TargetId.cosmwasm, TargetId.ton,
      TargetId.quint, TargetId.soroban, TargetId.openvm] do
    let out ← liftResult <| materializeSelected target mapCompiled
    expect (!(MaterializedArtifactsV1.filesOf out).isEmpty)
      s!"MapMini: {target} must materialize Map UInt64 UInt64"
  for target in [TargetId.icp] do
    match materializeSelected target mapCompiled with
    | .ok _ =>
        throw <| IO.userError s!"MapMini: {target} must decline Map state"
    | .error e =>
        expect ((e.render).contains "Map" ||
            (e.render).contains "container" ||
            (e.render).contains "anonymous" ||
            (e.render).contains "unsupported" ||
            (e.render).contains "pilot")
          s!"MapMini {target} message must cite Map/container boundary, got {e.render}"

  -- MapRetBox: Map UInt64 UInt64 *entry* return. NEAR/CW admit. EVM/Solana/
  -- Noir/Aleo/Psy/TON named B-RET FC; Quint names Q0 return; Soroban/
  -- OpenVM/ICP stay Map-pilot. Entry peek, not Map index get (Option).
  -- Not opening Map return ABI. MapMini state pin stays.
  let mapRetSource :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program MapRetBox where\n" ++
    "  state m : Map UInt64 UInt64\n\n" ++
    "  init() do\n" ++
    "    m := Map.empty()\n\n" ++
    "  entry peek() : Map UInt64 UInt64 do\n" ++
    "    return m\n\n" ++
    "end ProofForgeV2.Examples\n"
  let mapRetV1 ← match ← session.selectProgramV1 mapRetSource
      "<targets-map-ret>" "Examples.MapRetBox" none with
    | .ok v => pure v
    | .error e => throw <| IO.userError s!"MapRetBox select: {e.render}"
  let mapRetCompiled ← liftResult <| Compiler.compileValidatedSourceV1 mapRetV1
  for target in [TargetId.near, TargetId.cosmwasm] do
    let out ← liftResult <| materializeSelected target mapRetCompiled
    expect (!(MaterializedArtifactsV1.filesOf out).isEmpty)
      s!"MapRetBox: {target} must materialize Map UInt64 return"
  expectMaterializePlanInvariantV1 "MapRetBox" TargetId.evm TargetKind.evm
    mapRetCompiled "cannot return Map"
  expectMaterializePlanInvariantV1 "MapRetBox" TargetId.solana TargetKind.solana
    mapRetCompiled "cannot return anonymous Map"
  expectMaterializePlanInvariantV1 "MapRetBox" TargetId.noir TargetKind.noir
    mapRetCompiled "anonymous Map return is outside the Noir B-RET ABI"
  expectMaterializePlanInvariantV1 "MapRetBox" TargetId.aleo TargetKind.aleo
    mapRetCompiled "anonymous Map return is outside the Aleo B-RET ABI"
  expectMaterializePlanInvariantV1 "MapRetBox" TargetId.psy TargetKind.psy
    mapRetCompiled "anonymous Map return is outside the Psy B-RET ABI"
  expectMaterializePlanInvariantV1 "MapRetBox" TargetId.ton TargetKind.ton
    mapRetCompiled "entry 'peek' cannot return multi-leaf aggregate"
  expectMaterializePlanInvariantV1 "MapRetBox" TargetId.quint TargetKind.quint
    mapRetCompiled "Array/Map return is outside Q0"
  expectMaterializePlanInvariantV1 "MapRetBox" TargetId.soroban TargetKind.soroban
    mapRetCompiled "Array/Map return is outside S0"
  expectMaterializePlanInvariantV1 "MapRetBox" TargetId.openvm TargetKind.openvm
    mapRetCompiled "Array/Map return is outside O0"
  expectMaterializePlanInvariantV1 "MapRetBox" TargetId.icp TargetKind.icp
    mapRetCompiled "anonymous Map is outside the current container-state pilot"

  -- MapOpt: Map UInt64 Option UInt64 state. All twelve targets stay named
  -- Map-value/pilot FC. Not opening Map-of-Option. MapMini / MapRetBox stay.
  let mapOptSource :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program MapOpt where\n" ++
    "  state m : Map UInt64 Option UInt64\n\n" ++
    "  init() do\n" ++
    "    m := Map.empty()\n\n" ++
    "  entry put(k : UInt64, v : UInt64) : UInt64 do\n" ++
    "    m[k] := Option.some(v)\n" ++
    "    return v\n\n" ++
    "end ProofForgeV2.Examples\n"
  let mapOptV1 ← match ← session.selectProgramV1 mapOptSource
      "<targets-map-opt>" "Examples.MapOpt" none with
    | .ok v => pure v
    | .error e => throw <| IO.userError s!"MapOpt select: {e.render}"
  let mapOptCompiled ← liftResult <| Compiler.compileValidatedSourceV1 mapOptV1
  expectMaterializePlanInvariantV1 "MapOpt" TargetId.evm TargetKind.evm
    mapOptCompiled "Map index value must be UInt64"
  expectMaterializePlanInvariantV1 "MapOpt" TargetId.solana TargetKind.solana
    mapOptCompiled "Map state value must be UInt64"
  expectMaterializePlanInvariantV1 "MapOpt" TargetId.psy TargetKind.psy
    mapOptCompiled "Map state pilot requires UInt64 keys and values"
  for (target, kind) in #[
      (TargetId.near, TargetKind.near),
      (TargetId.noir, TargetKind.noir),
      (TargetId.aleo, TargetKind.aleo),
      (TargetId.cosmwasm, TargetKind.cosmwasm),
      (TargetId.ton, TargetKind.ton)] do
    expectMaterializePlanInvariantV1 "MapOpt" target kind mapOptCompiled
      "Map state admits only Map UInt64 UInt64"
  -- Quint admits Map type so Map-of-Option fails on the UInt64-value
  -- needle. Soroban/OpenVM stay Map-pilot; ICP stays Option-pilot.
  for (target, kind) in #[
      (TargetId.quint, TargetKind.quint),
      (TargetId.soroban, TargetKind.soroban),
      (TargetId.openvm, TargetKind.openvm)] do
    expectMaterializePlanInvariantV1 "MapOpt" target kind mapOptCompiled
      "Map state admits only Map UInt64 UInt64"
  expectMaterializePlanInvariantV1 "MapOpt" TargetId.icp TargetKind.icp
    mapOptCompiled "anonymous Option is outside the current container-state pilot"

  -- MapArr: Map UInt64 Array UInt64 2 state. All twelve targets stay named
  -- Map-value/pilot FC. Not opening Map-of-Array. MapOpt / MapMini /
  -- ArrayBox stay.
  let mapArrSource :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program MapArr where\n" ++
    "  state m : Map UInt64 Array UInt64 2\n\n" ++
    "  init() do\n" ++
    "    m := Map.empty()\n\n" ++
    "  entry put(k : UInt64, v : UInt64) : UInt64 do\n" ++
    "    return v\n\n" ++
    "end ProofForgeV2.Examples\n"
  let mapArrV1 ← match ← session.selectProgramV1 mapArrSource
      "<targets-map-arr>" "Examples.MapArr" none with
    | .ok v => pure v
    | .error e => throw <| IO.userError s!"MapArr select: {e.render}"
  let mapArrCompiled ← liftResult <| Compiler.compileValidatedSourceV1 mapArrV1
  for (target, kind) in #[
      (TargetId.evm, TargetKind.evm),
      (TargetId.solana, TargetKind.solana)] do
    expectMaterializePlanInvariantV1 "MapArr" target kind mapArrCompiled
      "Map state value must be UInt64"
  expectMaterializePlanInvariantV1 "MapArr" TargetId.psy TargetKind.psy
    mapArrCompiled "Map state pilot requires UInt64 keys and values"
  for (target, kind) in #[
      (TargetId.near, TargetKind.near),
      (TargetId.noir, TargetKind.noir),
      (TargetId.aleo, TargetKind.aleo),
      (TargetId.cosmwasm, TargetKind.cosmwasm),
      (TargetId.ton, TargetKind.ton)] do
    expectMaterializePlanInvariantV1 "MapArr" target kind mapArrCompiled
      "Map state admits only Map UInt64 UInt64"
  for (target, kind) in #[
      (TargetId.quint, TargetKind.quint),
      (TargetId.soroban, TargetKind.soroban),
      (TargetId.openvm, TargetKind.openvm)] do
    expectMaterializePlanInvariantV1 "MapArr" target kind mapArrCompiled
      "Map state admits only Map UInt64 UInt64"
  expectMaterializePlanInvariantV1 "MapArr" TargetId.icp TargetKind.icp
    mapArrCompiled "anonymous Map is outside the current container-state pilot"

  -- MapBytes: Map UInt64 Bytes 4 state. All twelve targets stay named
  -- Map-value/pilot FC. Not opening Map-of-Bytes. MapArr / MapOpt /
  -- BytesBox stay.
  let mapBytesSource :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program MapBytes where\n" ++
    "  state m : Map UInt64 Bytes 4\n\n" ++
    "  init() do\n" ++
    "    m := Map.empty()\n\n" ++
    "  entry put(k : UInt64, v : UInt64) : UInt64 do\n" ++
    "    return v\n\n" ++
    "end ProofForgeV2.Examples\n"
  let mapBytesV1 ← match ← session.selectProgramV1 mapBytesSource
      "<targets-map-bytes>" "Examples.MapBytes" none with
    | .ok v => pure v
    | .error e => throw <| IO.userError s!"MapBytes select: {e.render}"
  let mapBytesCompiled ← liftResult <| Compiler.compileValidatedSourceV1 mapBytesV1
  for (target, kind) in #[
      (TargetId.evm, TargetKind.evm),
      (TargetId.solana, TargetKind.solana)] do
    expectMaterializePlanInvariantV1 "MapBytes" target kind mapBytesCompiled
      "Map state value must be UInt64"
  expectMaterializePlanInvariantV1 "MapBytes" TargetId.psy TargetKind.psy
    mapBytesCompiled "Map state pilot requires UInt64 keys and values"
  for (target, kind) in #[
      (TargetId.near, TargetKind.near),
      (TargetId.noir, TargetKind.noir),
      (TargetId.aleo, TargetKind.aleo),
      (TargetId.cosmwasm, TargetKind.cosmwasm),
      (TargetId.ton, TargetKind.ton)] do
    expectMaterializePlanInvariantV1 "MapBytes" target kind mapBytesCompiled
      "Map state admits only Map UInt64 UInt64"
  for (target, kind) in #[
      (TargetId.quint, TargetKind.quint),
      (TargetId.soroban, TargetKind.soroban),
      (TargetId.openvm, TargetKind.openvm),
      (TargetId.icp, TargetKind.icp)] do
    expectMaterializePlanInvariantV1 "MapBytes" target kind mapBytesCompiled
      "anonymous Bytes is outside the current container-state pilot"

  -- MapMap: Map UInt64 Map UInt64 UInt64 state. All twelve targets stay
  -- named Map-value/pilot FC. Not opening Map-of-Map. MapBytes / MapArr /
  -- MapMini stay.
  let mapMapSource :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program MapMap where\n" ++
    "  state m : Map UInt64 Map UInt64 UInt64\n\n" ++
    "  init() do\n" ++
    "    m := Map.empty()\n\n" ++
    "  entry put(k : UInt64, v : UInt64) : UInt64 do\n" ++
    "    return v\n\n" ++
    "end ProofForgeV2.Examples\n"
  let mapMapV1 ← match ← session.selectProgramV1 mapMapSource
      "<targets-map-map>" "Examples.MapMap" none with
    | .ok v => pure v
    | .error e => throw <| IO.userError s!"MapMap select: {e.render}"
  let mapMapCompiled ← liftResult <| Compiler.compileValidatedSourceV1 mapMapV1
  for (target, kind) in #[
      (TargetId.evm, TargetKind.evm),
      (TargetId.solana, TargetKind.solana)] do
    expectMaterializePlanInvariantV1 "MapMap" target kind mapMapCompiled
      "Map state value must be UInt64"
  expectMaterializePlanInvariantV1 "MapMap" TargetId.psy TargetKind.psy
    mapMapCompiled "Map state pilot requires UInt64 keys and values"
  for (target, kind) in #[
      (TargetId.near, TargetKind.near),
      (TargetId.noir, TargetKind.noir),
      (TargetId.aleo, TargetKind.aleo),
      (TargetId.cosmwasm, TargetKind.cosmwasm),
      (TargetId.ton, TargetKind.ton)] do
    expectMaterializePlanInvariantV1 "MapMap" target kind mapMapCompiled
      "Map state admits only Map UInt64 UInt64"
  for (target, kind) in #[
      (TargetId.quint, TargetKind.quint),
      (TargetId.soroban, TargetKind.soroban),
      (TargetId.openvm, TargetKind.openvm)] do
    expectMaterializePlanInvariantV1 "MapMap" target kind mapMapCompiled
      "Map state admits only Map UInt64 UInt64"
  expectMaterializePlanInvariantV1 "MapMap" TargetId.icp TargetKind.icp
    mapMapCompiled "anonymous Map is outside the current container-state pilot"

  -- MapBytesKey: Map Bytes 4 UInt64 state. Bytes *key*, distinct from
  -- MapBytes (Bytes *value*). All twelve stay named key/pilot FC.
  -- EVM/Solana name the Principal-key alternative. Not opening Bytes-key
  -- Map. MapBytes / MapMap / BytesBox stay. No Bytes param.
  let mapBytesKeySource :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program MapBytesKey where\n" ++
    "  state m : Map Bytes 4 UInt64\n\n" ++
    "  init() do\n" ++
    "    m := Map.empty()\n\n" ++
    "  entry put(v : UInt64) : UInt64 do\n" ++
    "    return v\n\n" ++
    "end ProofForgeV2.Examples\n"
  let mapBytesKeyV1 ← match ← session.selectProgramV1 mapBytesKeySource
      "<targets-map-bytes-key>" "Examples.MapBytesKey" none with
    | .ok v => pure v
    | .error e => throw <| IO.userError s!"MapBytesKey select: {e.render}"
  let mapBytesKeyCompiled ← liftResult <| Compiler.compileValidatedSourceV1 mapBytesKeyV1
  for (target, kind) in #[
      (TargetId.evm, TargetKind.evm),
      (TargetId.solana, TargetKind.solana)] do
    expectMaterializePlanInvariantV1 "MapBytesKey" target kind mapBytesKeyCompiled
      "Map state admits only Map UInt64 UInt64 or Map Principal UInt64"
  expectMaterializePlanInvariantV1 "MapBytesKey" TargetId.psy TargetKind.psy
    mapBytesKeyCompiled "Map state pilot requires UInt64 keys and values"
  for (target, kind) in #[
      (TargetId.near, TargetKind.near),
      (TargetId.noir, TargetKind.noir),
      (TargetId.aleo, TargetKind.aleo),
      (TargetId.cosmwasm, TargetKind.cosmwasm),
      (TargetId.ton, TargetKind.ton)] do
    expectMaterializePlanInvariantV1 "MapBytesKey" target kind mapBytesKeyCompiled
      "Map state admits only Map UInt64 UInt64"
  for (target, kind) in #[
      (TargetId.quint, TargetKind.quint),
      (TargetId.soroban, TargetKind.soroban),
      (TargetId.openvm, TargetKind.openvm),
      (TargetId.icp, TargetKind.icp)] do
    expectMaterializePlanInvariantV1 "MapBytesKey" target kind mapBytesKeyCompiled
      "anonymous Bytes is outside the current container-state pilot"

  -- MapPrin: Map Principal UInt64 state. EVM/Solana admit the Principal-key
  -- alternative named in MapBytesKey needles. Remaining ten stay named
  -- key/pilot/Principal FC. Not opening Principal-key Map on the decline
  -- set. MapBytesKey / PrincipalMix / PrincipalReturn stay.
  let mapPrinSource :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program MapPrin where\n" ++
    "  state m : Map Principal UInt64\n\n" ++
    "  init() do\n" ++
    "    m := Map.empty()\n\n" ++
    "  entry put(k : Principal, v : UInt64) : UInt64 do\n" ++
    "    m[k] := v\n" ++
    "    return v\n\n" ++
    "end ProofForgeV2.Examples\n"
  let mapPrinV1 ← match ← session.selectProgramV1 mapPrinSource
      "<targets-map-prin>" "Examples.MapPrin" none with
    | .ok v => pure v
    | .error e => throw <| IO.userError s!"MapPrin select: {e.render}"
  let mapPrinCompiled ← liftResult <| Compiler.compileValidatedSourceV1 mapPrinV1
  for target in [TargetId.evm, TargetId.solana] do
    let out ← liftResult <| materializeSelected target mapPrinCompiled
    expect (!(MaterializedArtifactsV1.filesOf out).isEmpty)
      s!"MapPrin: {target} must materialize Map Principal UInt64"
  for (target, kind) in #[
      (TargetId.near, TargetKind.near),
      (TargetId.noir, TargetKind.noir),
      (TargetId.cosmwasm, TargetKind.cosmwasm)] do
    expectMaterializePlanInvariantV1 "MapPrin" target kind mapPrinCompiled
      "Map state admits only Map UInt64 UInt64"
  expectMaterializePlanInvariantV1 "MapPrin" TargetId.psy TargetKind.psy
    mapPrinCompiled "Map state pilot requires UInt64 keys and values"
  expectMaterializePlanInvariantV1 "MapPrin" TargetId.aleo TargetKind.aleo
    mapPrinCompiled "Principal/String stay fail-closed"
  expectMaterializePlanInvariantV1 "MapPrin" TargetId.quint TargetKind.quint
    mapPrinCompiled "Map state admits only Map UInt64 UInt64"
  expectMaterializePlanInvariantV1 "MapPrin" TargetId.ton TargetKind.ton
    mapPrinCompiled "no Field/Principal"
  for (target, kind) in #[
      (TargetId.soroban, TargetKind.soroban),
      (TargetId.openvm, TargetKind.openvm)] do
    expectMaterializePlanInvariantV1 "MapPrin" target kind mapPrinCompiled
      "Principal/aggregates"
  expectMaterializePlanInvariantV1 "MapPrin" TargetId.icp TargetKind.icp
    mapPrinCompiled "Principal/aggregates/Map/Option/Bytes/String fail closed"

  -- MapField: Map UInt64 Field bn254_fr state. All twelve stay named
  -- Map-value/Field FC. Not opening Map-of-Field. MapPrin / MapMini /
  -- FieldMix / ArrField / OptField stay.
  let mapFieldSource :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program MapField where\n" ++
    "  state m : Map UInt64 Field bn254_fr\n\n" ++
    "  init() do\n" ++
    "    m := Map.empty()\n\n" ++
    "  entry put(k : UInt64, v : UInt64) : UInt64 do\n" ++
    "    return v\n\n" ++
    "end ProofForgeV2.Examples\n"
  let mapFieldV1 ← match ← session.selectProgramV1 mapFieldSource
      "<targets-map-field>" "Examples.MapField" none with
    | .ok v => pure v
    | .error e => throw <| IO.userError s!"MapField select: {e.render}"
  let mapFieldCompiled ← liftResult <| Compiler.compileValidatedSourceV1 mapFieldV1
  expectMaterializePlanInvariantV1 "MapField" TargetId.evm TargetKind.evm
    mapFieldCompiled "Map state value must be UInt64"
  for (target, kind) in #[
      (TargetId.solana, TargetKind.solana),
      (TargetId.near, TargetKind.near)] do
    expectMaterializePlanInvariantV1 "MapField" target kind mapFieldCompiled
      "no native Field"
  expectMaterializePlanInvariantV1 "MapField" TargetId.noir TargetKind.noir
    mapFieldCompiled "Map state admits only Map UInt64 UInt64"
  expectMaterializePlanInvariantV1 "MapField" TargetId.aleo TargetKind.aleo
    mapFieldCompiled "bn254 Fr and Goldilocks fail closed as wrong modulus"
  expectMaterializePlanInvariantV1 "MapField" TargetId.psy TargetKind.psy
    mapFieldCompiled "bn254 Fr and BLS12-377 Fr fail closed as wrong modulus"
  expectMaterializePlanInvariantV1 "MapField" TargetId.quint TargetKind.quint
    mapFieldCompiled "narrow Int/Field/aggregates/Bytes fail closed"
  expectMaterializePlanInvariantV1 "MapField" TargetId.cosmwasm TargetKind.cosmwasm
    mapFieldCompiled "no Field"
  expectMaterializePlanInvariantV1 "MapField" TargetId.ton TargetKind.ton
    mapFieldCompiled "no Field/Principal"
  for (target, kind) in #[
      (TargetId.soroban, TargetKind.soroban),
      (TargetId.openvm, TargetKind.openvm)] do
    expectMaterializePlanInvariantV1 "MapField" target kind mapFieldCompiled
      "Int/Field/Principal/aggregates/Bytes"
  expectMaterializePlanInvariantV1 "MapField" TargetId.icp TargetKind.icp
    mapFieldCompiled "Int/Field/Principal/aggregates/Map/Option/Bytes/String fail closed"

  -- MapStr: Map UInt64 String state. All twelve stay named Map-value/String
  -- FC. Not opening Map-of-String. MapField / MapMini /
  -- StringInterfaceBoundary / ArrStr / OptStr stay.
  let mapStrSource :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program MapStr where\n" ++
    "  state m : Map UInt64 String\n\n" ++
    "  init() do\n" ++
    "    m := Map.empty()\n\n" ++
    "  entry put(k : UInt64, v : UInt64) : UInt64 do\n" ++
    "    return v\n\n" ++
    "end ProofForgeV2.Examples\n"
  let mapStrV1 ← match ← session.selectProgramV1 mapStrSource
      "<targets-map-str>" "Examples.MapStr" none with
    | .ok v => pure v
    | .error e => throw <| IO.userError s!"MapStr select: {e.render}"
  let mapStrCompiled ← liftResult <| Compiler.compileValidatedSourceV1 mapStrV1
  expectMaterializePlanInvariantV1 "MapStr" TargetId.evm TargetKind.evm
    mapStrCompiled "Map state value must be UInt64"
  expectMaterializePlanInvariantV1 "MapStr" TargetId.solana TargetKind.solana
    mapStrCompiled "not a fixed 32-byte pubkey"
  expectMaterializePlanInvariantV1 "MapStr" TargetId.near TargetKind.near
    mapStrCompiled "not a NEAR account-id string"
  expectMaterializePlanInvariantV1 "MapStr" TargetId.noir TargetKind.noir
    mapStrCompiled "not a Field element"
  expectMaterializePlanInvariantV1 "MapStr" TargetId.aleo TargetKind.aleo
    mapStrCompiled "Principal/String stay fail-closed"
  expectMaterializePlanInvariantV1 "MapStr" TargetId.psy TargetKind.psy
    mapStrCompiled "Map state pilot requires UInt64 keys and values"
  expectMaterializePlanInvariantV1 "MapStr" TargetId.quint TargetKind.quint
    mapStrCompiled "narrow Int/Field/aggregates/Bytes fail closed"
  expectMaterializePlanInvariantV1 "MapStr" TargetId.cosmwasm TargetKind.cosmwasm
    mapStrCompiled "no Field"
  expectMaterializePlanInvariantV1 "MapStr" TargetId.ton TargetKind.ton
    mapStrCompiled "no Field/Principal"
  for (target, kind) in #[
      (TargetId.soroban, TargetKind.soroban),
      (TargetId.openvm, TargetKind.openvm)] do
    expectMaterializePlanInvariantV1 "MapStr" target kind mapStrCompiled
      "Int/Field/Principal/aggregates/Bytes"
  expectMaterializePlanInvariantV1 "MapStr" TargetId.icp TargetKind.icp
    mapStrCompiled "Map/Option/Bytes/String fail closed"

  -- MapBool: Map UInt64 Bool state. All twelve stay named Map-value/pilot
  -- FC. Not opening Map-of-Bool. MapStr / MapMini / ArrBool / OptBool stay.
  let mapBoolSource :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program MapBool where\n" ++
    "  state m : Map UInt64 Bool\n\n" ++
    "  init() do\n" ++
    "    m := Map.empty()\n\n" ++
    "  entry put(k : UInt64, v : UInt64) : UInt64 do\n" ++
    "    return v\n\n" ++
    "end ProofForgeV2.Examples\n"
  let mapBoolV1 ← match ← session.selectProgramV1 mapBoolSource
      "<targets-map-bool>" "Examples.MapBool" none with
    | .ok v => pure v
    | .error e => throw <| IO.userError s!"MapBool select: {e.render}"
  let mapBoolCompiled ← liftResult <| Compiler.compileValidatedSourceV1 mapBoolV1
  for (target, kind) in #[
      (TargetId.evm, TargetKind.evm),
      (TargetId.solana, TargetKind.solana)] do
    expectMaterializePlanInvariantV1 "MapBool" target kind mapBoolCompiled
      "Map state value must be UInt64"
  for (target, kind) in #[
      (TargetId.near, TargetKind.near),
      (TargetId.noir, TargetKind.noir),
      (TargetId.aleo, TargetKind.aleo),
      (TargetId.cosmwasm, TargetKind.cosmwasm),
      (TargetId.ton, TargetKind.ton)] do
    expectMaterializePlanInvariantV1 "MapBool" target kind mapBoolCompiled
      "Map state admits only Map UInt64 UInt64"
  expectMaterializePlanInvariantV1 "MapBool" TargetId.psy TargetKind.psy
    mapBoolCompiled "Map state pilot requires UInt64 keys and values"
  for (target, kind) in #[
      (TargetId.quint, TargetKind.quint),
      (TargetId.soroban, TargetKind.soroban),
      (TargetId.openvm, TargetKind.openvm)] do
    expectMaterializePlanInvariantV1 "MapBool" target kind mapBoolCompiled
      "Map state admits only Map UInt64 UInt64"
  expectMaterializePlanInvariantV1 "MapBool" TargetId.icp TargetKind.icp
    mapBoolCompiled "anonymous Map is outside the current container-state pilot"

  -- MapInt: Map UInt64 Int64 state. EVM (hashed 1-slot) + Solana/NEAR/Noir/
  -- Aleo/Psy/CW/TON admit unsigned key + signed val. Envelope-4 stay named
  -- FC on this mixed UInt64-param program. Not opening Map-of-Int8,
  -- Int64-key, or Map UInt128.
  let mapIntSource :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program MapInt where\n" ++
    "  state m : Map UInt64 Int64\n\n" ++
    "  init() do\n" ++
    "    m := Map.empty()\n\n" ++
    "  entry put(k : UInt64, v : UInt64) : UInt64 do\n" ++
    "    return v\n\n" ++
    "end ProofForgeV2.Examples\n"
  let mapIntV1 ← match ← session.selectProgramV1 mapIntSource
      "<targets-map-int>" "Examples.MapInt" none with
    | .ok v => pure v
    | .error e => throw <| IO.userError s!"MapInt select: {e.render}"
  let mapIntCompiled ← liftResult <| Compiler.compileValidatedSourceV1 mapIntV1
  let mapIntEvmOut ← liftResult <| materializeSelected TargetId.evm mapIntCompiled
  expect (!(MaterializedArtifactsV1.filesOf mapIntEvmOut).isEmpty)
    "MapInt: evm must materialize Map UInt64 Int64"
  let mapIntSolOut ← liftResult <| materializeSelected TargetId.solana mapIntCompiled
  expect (!(MaterializedArtifactsV1.filesOf mapIntSolOut).isEmpty)
    "MapInt: solana must materialize Map UInt64 Int64"
  let mapIntCwOut ← liftResult <| materializeSelected TargetId.cosmwasm mapIntCompiled
  expect (!(MaterializedArtifactsV1.filesOf mapIntCwOut).isEmpty)
    "MapInt: cosmwasm must materialize Map UInt64 Int64"
  let mapIntTonOut ← liftResult <| materializeSelected TargetId.ton mapIntCompiled
  expect (!(MaterializedArtifactsV1.filesOf mapIntTonOut).isEmpty)
    "MapInt: ton must materialize Map UInt64 Int64"
  let mapIntNearOut ← liftResult <| materializeSelected TargetId.near mapIntCompiled
  expect (!(MaterializedArtifactsV1.filesOf mapIntNearOut).isEmpty)
    "MapInt: near must materialize Map UInt64 Int64"
  let mapIntNoirOut ← liftResult <| materializeSelected TargetId.noir mapIntCompiled
  expect (!(MaterializedArtifactsV1.filesOf mapIntNoirOut).isEmpty)
    "MapInt: noir must materialize Map UInt64 Int64"
  let mapIntAleoOut ← liftResult <| materializeSelected TargetId.aleo mapIntCompiled
  expect (!(MaterializedArtifactsV1.filesOf mapIntAleoOut).isEmpty)
    "MapInt: aleo must materialize Map UInt64 Int64"
  let mapIntPsyOut ← liftResult <| materializeSelected TargetId.psy mapIntCompiled
  expect (!(MaterializedArtifactsV1.filesOf mapIntPsyOut).isEmpty)
    "MapInt: psy must materialize Map UInt64 Int64"
  for (target, kind) in #[
      (TargetId.quint, TargetKind.quint),
      (TargetId.soroban, TargetKind.soroban),
      (TargetId.openvm, TargetKind.openvm)] do
    expectMaterializePlanInvariantV1 "MapInt" target kind mapIntCompiled
      "Map state admits only Map UInt64 UInt64"
  expectMaterializePlanInvariantV1 "MapInt" TargetId.icp TargetKind.icp
    mapIntCompiled "anonymous Map is outside the current container-state pilot"

  -- MapIntKey: Map Int64 UInt64 state (signed KEY). EVM/Solana stay on
  -- the key-shape needle, not MapInt's value needle. Six targets stay
  -- Map-U64-U64; Psy stays pilot; envelope-4 admit Int64 width so they
  -- fail on the Map-pilot. Not opening Int64-key Map. MapInt / MapBool /
  -- MapPrin / ArrInt / OptInt stay.
  let mapIntKeySource :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program MapIntKey where\n" ++
    "  state m : Map Int64 UInt64\n\n" ++
    "  init() do\n" ++
    "    m := Map.empty()\n\n" ++
    "  entry put(k : UInt64, v : UInt64) : UInt64 do\n" ++
    "    return v\n\n" ++
    "end ProofForgeV2.Examples\n"
  let mapIntKeyV1 ← match ← session.selectProgramV1 mapIntKeySource
      "<targets-map-int-key>" "Examples.MapIntKey" none with
    | .ok v => pure v
    | .error e => throw <| IO.userError s!"MapIntKey select: {e.render}"
  let mapIntKeyCompiled ← liftResult <| Compiler.compileValidatedSourceV1 mapIntKeyV1
  for (target, kind) in #[
      (TargetId.evm, TargetKind.evm),
      (TargetId.solana, TargetKind.solana)] do
    expectMaterializePlanInvariantV1 "MapIntKey" target kind mapIntKeyCompiled
      "Map state admits only Map UInt64 UInt64 or Map Principal UInt64"
  for (target, kind) in #[
      (TargetId.near, TargetKind.near),
      (TargetId.noir, TargetKind.noir),
      (TargetId.aleo, TargetKind.aleo),
      (TargetId.cosmwasm, TargetKind.cosmwasm),
      (TargetId.ton, TargetKind.ton)] do
    expectMaterializePlanInvariantV1 "MapIntKey" target kind mapIntKeyCompiled
      "Map state admits only Map UInt64 UInt64"
  expectMaterializePlanInvariantV1 "MapIntKey" TargetId.psy TargetKind.psy
    mapIntKeyCompiled "Map state pilot requires UInt64 keys and values"
  for (target, kind) in #[
      (TargetId.quint, TargetKind.quint),
      (TargetId.soroban, TargetKind.soroban),
      (TargetId.openvm, TargetKind.openvm)] do
    expectMaterializePlanInvariantV1 "MapIntKey" target kind mapIntKeyCompiled
      "Map state admits only Map UInt64 UInt64"
  expectMaterializePlanInvariantV1 "MapIntKey" TargetId.icp TargetKind.icp
    mapIntKeyCompiled "anonymous Map is outside the current container-state pilot"

  -- MapU128: Map UInt64 UInt128 state. All twelve stay named FC. Aleo
  -- and TON share the Map-U64-U64 needle (UInt128 width is admitted).
  -- Quint/Soroban/OpenVM/ICP stay on the UInt64 width needle. Not
  -- opening Map-of-UInt128.
  let mapU128Source :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program MapU128 where\n" ++
    "  state m : Map UInt64 UInt128\n\n" ++
    "  init() do\n" ++
    "    m := Map.empty()\n\n" ++
    "  entry put(k : UInt64, v : UInt64) : UInt64 do\n" ++
    "    return v\n\n" ++
    "end ProofForgeV2.Examples\n"
  let mapU128V1 ← match ← session.selectProgramV1 mapU128Source
      "<targets-map-u128>" "Examples.MapU128" none with
    | .ok v => pure v
    | .error e => throw <| IO.userError s!"MapU128 select: {e.render}"
  let mapU128Compiled ← liftResult <| Compiler.compileValidatedSourceV1 mapU128V1
  for (target, kind) in #[
      (TargetId.evm, TargetKind.evm),
      (TargetId.solana, TargetKind.solana)] do
    expectMaterializePlanInvariantV1 "MapU128" target kind mapU128Compiled
      "Map state value must be UInt64"
  for (target, kind) in #[
      (TargetId.near, TargetKind.near),
      (TargetId.noir, TargetKind.noir),
      (TargetId.cosmwasm, TargetKind.cosmwasm),
      (TargetId.aleo, TargetKind.aleo)] do
    expectMaterializePlanInvariantV1 "MapU128" target kind mapU128Compiled
      "Map state admits only Map UInt64 UInt64"
  expectMaterializePlanInvariantV1 "MapU128" TargetId.psy TargetKind.psy
    mapU128Compiled "Map state pilot requires UInt64 keys and values"
  expectMaterializePlanInvariantV1 "MapU128" TargetId.ton TargetKind.ton
    mapU128Compiled "Map state admits only Map UInt64 UInt64"
  for (target, kind) in #[
      (TargetId.quint, TargetKind.quint),
      (TargetId.soroban, TargetKind.soroban),
      (TargetId.openvm, TargetKind.openvm),
      (TargetId.icp, TargetKind.icp)] do
    expectMaterializePlanInvariantV1 "MapU128" target kind mapU128Compiled
      "only anonymous UInt64/Int64 widths are supported"

  -- MapU256: Map UInt64 UInt256 state. Same twelve named-FC needles as
  -- MapU128, but UInt256 ≠ UInt128 so it is its own pin. Aleo stays on
  -- width; TON now uses Map-U64-U64 (bare UInt256 is admitted). Not
  -- opening Map-of-UInt256. MapU128 / MapInt / MapIntKey / ArrU256 /
  -- WideUInt256 stay.
  let mapU256Source :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program MapU256 where\n" ++
    "  state m : Map UInt64 UInt256\n\n" ++
    "  init() do\n" ++
    "    m := Map.empty()\n\n" ++
    "  entry put(k : UInt64, v : UInt64) : UInt64 do\n" ++
    "    return v\n\n" ++
    "end ProofForgeV2.Examples\n"
  let mapU256V1 ← match ← session.selectProgramV1 mapU256Source
      "<targets-map-u256>" "Examples.MapU256" none with
    | .ok v => pure v
    | .error e => throw <| IO.userError s!"MapU256 select: {e.render}"
  let mapU256Compiled ← liftResult <| Compiler.compileValidatedSourceV1 mapU256V1
  for (target, kind) in #[
      (TargetId.evm, TargetKind.evm),
      (TargetId.solana, TargetKind.solana)] do
    expectMaterializePlanInvariantV1 "MapU256" target kind mapU256Compiled
      "Map state value must be UInt64"
  for (target, kind) in #[
      (TargetId.near, TargetKind.near),
      (TargetId.noir, TargetKind.noir),
      (TargetId.cosmwasm, TargetKind.cosmwasm)] do
    expectMaterializePlanInvariantV1 "MapU256" target kind mapU256Compiled
      "Map state admits only Map UInt64 UInt64"
  expectMaterializePlanInvariantV1 "MapU256" TargetId.psy TargetKind.psy
    mapU256Compiled "Map state pilot requires UInt64 keys and values"
  expectMaterializePlanInvariantV1 "MapU256" TargetId.aleo TargetKind.aleo
    mapU256Compiled "only anonymous UInt64/UInt32/UInt16/UInt8/UInt128/Int64/Int32/Int16/Int8 widths are supported"
  expectMaterializePlanInvariantV1 "MapU256" TargetId.ton TargetKind.ton
    mapU256Compiled "Map state admits only Map UInt64 UInt64"
  for (target, kind) in #[
      (TargetId.quint, TargetKind.quint),
      (TargetId.soroban, TargetKind.soroban),
      (TargetId.openvm, TargetKind.openvm),
      (TargetId.icp, TargetKind.icp)] do
    expectMaterializePlanInvariantV1 "MapU256" target kind mapU256Compiled
      "only anonymous UInt64/Int64 widths are supported"

  -- MapU128Key: Map UInt128 UInt64 state (unsigned 128-bit KEY).
  -- EVM/Solana stay on the key-shape needle, not MapU128's value
  -- needle. Aleo/TON share Map-U64-U64 (UInt128 width is admitted).
  -- UInt128-key ≠ UInt128-value and ≠ Int64-key. Not opening
  -- UInt128-key Map.
  let mapU128KeySource :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program MapU128Key where\n" ++
    "  state m : Map UInt128 UInt64\n\n" ++
    "  init() do\n" ++
    "    m := Map.empty()\n\n" ++
    "  entry put(k : UInt64, v : UInt64) : UInt64 do\n" ++
    "    return v\n\n" ++
    "end ProofForgeV2.Examples\n"
  let mapU128KeyV1 ← match ← session.selectProgramV1 mapU128KeySource
      "<targets-map-u128-key>" "Examples.MapU128Key" none with
    | .ok v => pure v
    | .error e => throw <| IO.userError s!"MapU128Key select: {e.render}"
  let mapU128KeyCompiled ← liftResult <| Compiler.compileValidatedSourceV1 mapU128KeyV1
  for (target, kind) in #[
      (TargetId.evm, TargetKind.evm),
      (TargetId.solana, TargetKind.solana)] do
    expectMaterializePlanInvariantV1 "MapU128Key" target kind mapU128KeyCompiled
      "Map state admits only Map UInt64 UInt64 or Map Principal UInt64"
  for (target, kind) in #[
      (TargetId.near, TargetKind.near),
      (TargetId.noir, TargetKind.noir),
      (TargetId.cosmwasm, TargetKind.cosmwasm),
      (TargetId.aleo, TargetKind.aleo)] do
    expectMaterializePlanInvariantV1 "MapU128Key" target kind mapU128KeyCompiled
      "Map state admits only Map UInt64 UInt64"
  expectMaterializePlanInvariantV1 "MapU128Key" TargetId.psy TargetKind.psy
    mapU128KeyCompiled "Map state pilot requires UInt64 keys and values"
  expectMaterializePlanInvariantV1 "MapU128Key" TargetId.ton TargetKind.ton
    mapU128KeyCompiled "Map state admits only Map UInt64 UInt64"
  for (target, kind) in #[
      (TargetId.quint, TargetKind.quint),
      (TargetId.soroban, TargetKind.soroban),
      (TargetId.openvm, TargetKind.openvm),
      (TargetId.icp, TargetKind.icp)] do
    expectMaterializePlanInvariantV1 "MapU128Key" target kind mapU128KeyCompiled
      "only anonymous UInt64/Int64 widths are supported"

  -- MapU256Key: Map UInt256 UInt64 state. Same twelve named-FC needles
  -- as MapU128Key, but UInt256-key ≠ UInt128-key so it is its own pin.
  -- EVM/Solana stay key-shape, not MapU256 value. Aleo stays width;
  -- TON now uses Map-U64-U64 (bare UInt256 is admitted). Not opening
  -- UInt256-key Map. MapU128Key / MapU256 / MapIntKey / OptU256 stay.
  let mapU256KeySource :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program MapU256Key where\n" ++
    "  state m : Map UInt256 UInt64\n\n" ++
    "  init() do\n" ++
    "    m := Map.empty()\n\n" ++
    "  entry put(k : UInt64, v : UInt64) : UInt64 do\n" ++
    "    return v\n\n" ++
    "end ProofForgeV2.Examples\n"
  let mapU256KeyV1 ← match ← session.selectProgramV1 mapU256KeySource
      "<targets-map-u256-key>" "Examples.MapU256Key" none with
    | .ok v => pure v
    | .error e => throw <| IO.userError s!"MapU256Key select: {e.render}"
  let mapU256KeyCompiled ← liftResult <| Compiler.compileValidatedSourceV1 mapU256KeyV1
  for (target, kind) in #[
      (TargetId.evm, TargetKind.evm),
      (TargetId.solana, TargetKind.solana)] do
    expectMaterializePlanInvariantV1 "MapU256Key" target kind mapU256KeyCompiled
      "Map state admits only Map UInt64 UInt64 or Map Principal UInt64"
  for (target, kind) in #[
      (TargetId.near, TargetKind.near),
      (TargetId.noir, TargetKind.noir),
      (TargetId.cosmwasm, TargetKind.cosmwasm)] do
    expectMaterializePlanInvariantV1 "MapU256Key" target kind mapU256KeyCompiled
      "Map state admits only Map UInt64 UInt64"
  expectMaterializePlanInvariantV1 "MapU256Key" TargetId.psy TargetKind.psy
    mapU256KeyCompiled "Map state pilot requires UInt64 keys and values"
  expectMaterializePlanInvariantV1 "MapU256Key" TargetId.aleo TargetKind.aleo
    mapU256KeyCompiled "only anonymous UInt64/UInt32/UInt16/UInt8/UInt128/Int64/Int32/Int16/Int8 widths are supported"
  expectMaterializePlanInvariantV1 "MapU256Key" TargetId.ton TargetKind.ton
    mapU256KeyCompiled "Map state admits only Map UInt64 UInt64"
  for (target, kind) in #[
      (TargetId.quint, TargetKind.quint),
      (TargetId.soroban, TargetKind.soroban),
      (TargetId.openvm, TargetKind.openvm),
      (TargetId.icp, TargetKind.icp)] do
    expectMaterializePlanInvariantV1 "MapU256Key" target kind mapU256KeyCompiled
      "only anonymous UInt64/Int64 widths are supported"

  -- MapU32Key: Map UInt32 UInt64 state. UInt32 is a legal Aleo/TON
  -- width, so those two stay on Map-U64-U64, not MapU128Key's width
  -- needles. EVM/Solana stay key-shape. Not opening UInt32-key Map.
  -- MapU128Key / MapU256Key / MapIntKey / MapU256 stay.
  let mapU32KeySource :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program MapU32Key where\n" ++
    "  state m : Map UInt32 UInt64\n\n" ++
    "  init() do\n" ++
    "    m := Map.empty()\n\n" ++
    "  entry put(k : UInt64, v : UInt64) : UInt64 do\n" ++
    "    return v\n\n" ++
    "end ProofForgeV2.Examples\n"
  let mapU32KeyV1 ← match ← session.selectProgramV1 mapU32KeySource
      "<targets-map-u32-key>" "Examples.MapU32Key" none with
    | .ok v => pure v
    | .error e => throw <| IO.userError s!"MapU32Key select: {e.render}"
  let mapU32KeyCompiled ← liftResult <| Compiler.compileValidatedSourceV1 mapU32KeyV1
  for (target, kind) in #[
      (TargetId.evm, TargetKind.evm),
      (TargetId.solana, TargetKind.solana)] do
    expectMaterializePlanInvariantV1 "MapU32Key" target kind mapU32KeyCompiled
      "Map state admits only Map UInt64 UInt64 or Map Principal UInt64"
  for (target, kind) in #[
      (TargetId.near, TargetKind.near),
      (TargetId.noir, TargetKind.noir),
      (TargetId.aleo, TargetKind.aleo),
      (TargetId.cosmwasm, TargetKind.cosmwasm),
      (TargetId.ton, TargetKind.ton)] do
    expectMaterializePlanInvariantV1 "MapU32Key" target kind mapU32KeyCompiled
      "Map state admits only Map UInt64 UInt64"
  expectMaterializePlanInvariantV1 "MapU32Key" TargetId.psy TargetKind.psy
    mapU32KeyCompiled "Map state pilot requires UInt64 keys and values"
  for (target, kind) in #[
      (TargetId.quint, TargetKind.quint),
      (TargetId.soroban, TargetKind.soroban),
      (TargetId.openvm, TargetKind.openvm)] do
    expectMaterializePlanInvariantV1 "MapU32Key" target kind mapU32KeyCompiled
      "Map state admits only Map UInt64 UInt64"
  expectMaterializePlanInvariantV1 "MapU32Key" TargetId.icp TargetKind.icp
    mapU32KeyCompiled "anonymous Map is outside the current container-state pilot"

  -- MapU32: Map UInt64 UInt32 state (unsigned 32-bit VALUE). EVM/Solana
  -- stay on the value needle, not MapU32Key's key-shape. UInt32 is a
  -- legal Aleo/TON width, so those two stay on Map-U64-U64, not
  -- MapU128's width needles. Not opening Map-of-UInt32. MapU32Key /
  -- MapInt / MapU128 / MapU256 stay.
  let mapU32Source :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program MapU32 where\n" ++
    "  state m : Map UInt64 UInt32\n\n" ++
    "  init() do\n" ++
    "    m := Map.empty()\n\n" ++
    "  entry put(k : UInt64, v : UInt64) : UInt64 do\n" ++
    "    return v\n\n" ++
    "end ProofForgeV2.Examples\n"
  let mapU32V1 ← match ← session.selectProgramV1 mapU32Source
      "<targets-map-u32>" "Examples.MapU32" none with
    | .ok v => pure v
    | .error e => throw <| IO.userError s!"MapU32 select: {e.render}"
  let mapU32Compiled ← liftResult <| Compiler.compileValidatedSourceV1 mapU32V1
  for (target, kind) in #[
      (TargetId.evm, TargetKind.evm),
      (TargetId.solana, TargetKind.solana)] do
    expectMaterializePlanInvariantV1 "MapU32" target kind mapU32Compiled
      "Map state value must be UInt64"
  for (target, kind) in #[
      (TargetId.near, TargetKind.near),
      (TargetId.noir, TargetKind.noir),
      (TargetId.aleo, TargetKind.aleo),
      (TargetId.cosmwasm, TargetKind.cosmwasm),
      (TargetId.ton, TargetKind.ton)] do
    expectMaterializePlanInvariantV1 "MapU32" target kind mapU32Compiled
      "Map state admits only Map UInt64 UInt64"
  expectMaterializePlanInvariantV1 "MapU32" TargetId.psy TargetKind.psy
    mapU32Compiled "Map state pilot requires UInt64 keys and values"
  for (target, kind) in #[
      (TargetId.quint, TargetKind.quint),
      (TargetId.soroban, TargetKind.soroban),
      (TargetId.openvm, TargetKind.openvm)] do
    expectMaterializePlanInvariantV1 "MapU32" target kind mapU32Compiled
      "Map state admits only Map UInt64 UInt64"
  expectMaterializePlanInvariantV1 "MapU32" TargetId.icp TargetKind.icp
    mapU32Compiled "anonymous Map is outside the current container-state pilot"

  -- MapU16Key: Map UInt16 UInt64 state. Same legal-width needle set as
  -- MapU32Key (Aleo/TON stay Map-U64-U64, not MapU128Key width
  -- needles). UInt16-key ≠ UInt32-key so this is its own pin. Not
  -- opening UInt16-key Map. MapU32Key / MapU32 / MapU128Key /
  -- MapIntKey stay.
  let mapU16KeySource :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program MapU16Key where\n" ++
    "  state m : Map UInt16 UInt64\n\n" ++
    "  init() do\n" ++
    "    m := Map.empty()\n\n" ++
    "  entry put(k : UInt64, v : UInt64) : UInt64 do\n" ++
    "    return v\n\n" ++
    "end ProofForgeV2.Examples\n"
  let mapU16KeyV1 ← match ← session.selectProgramV1 mapU16KeySource
      "<targets-map-u16-key>" "Examples.MapU16Key" none with
    | .ok v => pure v
    | .error e => throw <| IO.userError s!"MapU16Key select: {e.render}"
  let mapU16KeyCompiled ← liftResult <| Compiler.compileValidatedSourceV1 mapU16KeyV1
  for (target, kind) in #[
      (TargetId.evm, TargetKind.evm),
      (TargetId.solana, TargetKind.solana)] do
    expectMaterializePlanInvariantV1 "MapU16Key" target kind mapU16KeyCompiled
      "Map state admits only Map UInt64 UInt64 or Map Principal UInt64"
  for (target, kind) in #[
      (TargetId.near, TargetKind.near),
      (TargetId.noir, TargetKind.noir),
      (TargetId.aleo, TargetKind.aleo),
      (TargetId.cosmwasm, TargetKind.cosmwasm),
      (TargetId.ton, TargetKind.ton)] do
    expectMaterializePlanInvariantV1 "MapU16Key" target kind mapU16KeyCompiled
      "Map state admits only Map UInt64 UInt64"
  expectMaterializePlanInvariantV1 "MapU16Key" TargetId.psy TargetKind.psy
    mapU16KeyCompiled "Map state pilot requires UInt64 keys and values"
  for (target, kind) in #[
      (TargetId.quint, TargetKind.quint),
      (TargetId.soroban, TargetKind.soroban),
      (TargetId.openvm, TargetKind.openvm),
      (TargetId.icp, TargetKind.icp)] do
    expectMaterializePlanInvariantV1 "MapU16Key" target kind mapU16KeyCompiled
      "only anonymous UInt64/Int64 widths are supported"

  -- MapU8Key: Map UInt8 UInt64 state. Same legal-width needle set as
  -- MapU16Key, but UInt8-key ≠ UInt16-key so it is its own pin (last
  -- narrow unsigned Map key). Aleo/TON stay on Map-U64-U64, not
  -- MapU128Key's width needles. Not opening UInt8-key Map. MapU16Key /
  -- MapU32Key / MapU32 / OptU8 stay.
  let mapU8KeySource :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program MapU8Key where\n" ++
    "  state m : Map UInt8 UInt64\n\n" ++
    "  init() do\n" ++
    "    m := Map.empty()\n\n" ++
    "  entry put(k : UInt64, v : UInt64) : UInt64 do\n" ++
    "    return v\n\n" ++
    "end ProofForgeV2.Examples\n"
  let mapU8KeyV1 ← match ← session.selectProgramV1 mapU8KeySource
      "<targets-map-u8-key>" "Examples.MapU8Key" none with
    | .ok v => pure v
    | .error e => throw <| IO.userError s!"MapU8Key select: {e.render}"
  let mapU8KeyCompiled ← liftResult <| Compiler.compileValidatedSourceV1 mapU8KeyV1
  for (target, kind) in #[
      (TargetId.evm, TargetKind.evm),
      (TargetId.solana, TargetKind.solana)] do
    expectMaterializePlanInvariantV1 "MapU8Key" target kind mapU8KeyCompiled
      "Map state admits only Map UInt64 UInt64 or Map Principal UInt64"
  for (target, kind) in #[
      (TargetId.near, TargetKind.near),
      (TargetId.noir, TargetKind.noir),
      (TargetId.aleo, TargetKind.aleo),
      (TargetId.cosmwasm, TargetKind.cosmwasm),
      (TargetId.ton, TargetKind.ton)] do
    expectMaterializePlanInvariantV1 "MapU8Key" target kind mapU8KeyCompiled
      "Map state admits only Map UInt64 UInt64"
  expectMaterializePlanInvariantV1 "MapU8Key" TargetId.psy TargetKind.psy
    mapU8KeyCompiled "Map state pilot requires UInt64 keys and values"
  for (target, kind) in #[
      (TargetId.quint, TargetKind.quint),
      (TargetId.soroban, TargetKind.soroban),
      (TargetId.openvm, TargetKind.openvm),
      (TargetId.icp, TargetKind.icp)] do
    expectMaterializePlanInvariantV1 "MapU8Key" target kind mapU8KeyCompiled
      "only anonymous UInt64/Int64 widths are supported"

  -- MapU16: Map UInt64 UInt16 state (unsigned 16-bit VALUE). Same
  -- legal-width value needle set as MapU32, but UInt16-value ≠
  -- UInt32-value and ≠ UInt16-key. EVM/Solana stay on the value
  -- needle, not MapU16Key's key-shape. Aleo/TON stay on Map-U64-U64,
  -- not MapU128's width needles. Not opening Map-of-UInt16. MapU8Key /
  -- MapU16Key / MapU32 / MapU32Key stay.
  let mapU16Source :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program MapU16 where\n" ++
    "  state m : Map UInt64 UInt16\n\n" ++
    "  init() do\n" ++
    "    m := Map.empty()\n\n" ++
    "  entry put(k : UInt64, v : UInt64) : UInt64 do\n" ++
    "    return v\n\n" ++
    "end ProofForgeV2.Examples\n"
  let mapU16V1 ← match ← session.selectProgramV1 mapU16Source
      "<targets-map-u16>" "Examples.MapU16" none with
    | .ok v => pure v
    | .error e => throw <| IO.userError s!"MapU16 select: {e.render}"
  let mapU16Compiled ← liftResult <| Compiler.compileValidatedSourceV1 mapU16V1
  for (target, kind) in #[
      (TargetId.evm, TargetKind.evm),
      (TargetId.solana, TargetKind.solana)] do
    expectMaterializePlanInvariantV1 "MapU16" target kind mapU16Compiled
      "Map state value must be UInt64"
  for (target, kind) in #[
      (TargetId.near, TargetKind.near),
      (TargetId.noir, TargetKind.noir),
      (TargetId.aleo, TargetKind.aleo),
      (TargetId.cosmwasm, TargetKind.cosmwasm),
      (TargetId.ton, TargetKind.ton)] do
    expectMaterializePlanInvariantV1 "MapU16" target kind mapU16Compiled
      "Map state admits only Map UInt64 UInt64"
  expectMaterializePlanInvariantV1 "MapU16" TargetId.psy TargetKind.psy
    mapU16Compiled "Map state pilot requires UInt64 keys and values"
  for (target, kind) in #[
      (TargetId.quint, TargetKind.quint),
      (TargetId.soroban, TargetKind.soroban),
      (TargetId.openvm, TargetKind.openvm),
      (TargetId.icp, TargetKind.icp)] do
    expectMaterializePlanInvariantV1 "MapU16" target kind mapU16Compiled
      "only anonymous UInt64/Int64 widths are supported"

  -- MapU8: Map UInt64 UInt8 state (unsigned 8-bit VALUE). Same
  -- legal-width value needle set as MapU16, but UInt8-value ≠
  -- UInt16-value and ≠ UInt8-key (last narrow unsigned Map-value pin).
  -- EVM/Solana stay on the value needle, not MapU8Key's key-shape.
  -- Aleo/TON stay on Map-U64-U64. Not opening Map-of-UInt8. MapU16 /
  -- MapU8Key / MapU32 / MapU16Key stay.
  let mapU8Source :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program MapU8 where\n" ++
    "  state m : Map UInt64 UInt8\n\n" ++
    "  init() do\n" ++
    "    m := Map.empty()\n\n" ++
    "  entry put(k : UInt64, v : UInt64) : UInt64 do\n" ++
    "    return v\n\n" ++
    "end ProofForgeV2.Examples\n"
  let mapU8V1 ← match ← session.selectProgramV1 mapU8Source
      "<targets-map-u8>" "Examples.MapU8" none with
    | .ok v => pure v
    | .error e => throw <| IO.userError s!"MapU8 select: {e.render}"
  let mapU8Compiled ← liftResult <| Compiler.compileValidatedSourceV1 mapU8V1
  for (target, kind) in #[
      (TargetId.evm, TargetKind.evm),
      (TargetId.solana, TargetKind.solana)] do
    expectMaterializePlanInvariantV1 "MapU8" target kind mapU8Compiled
      "Map state value must be UInt64"
  for (target, kind) in #[
      (TargetId.near, TargetKind.near),
      (TargetId.noir, TargetKind.noir),
      (TargetId.aleo, TargetKind.aleo),
      (TargetId.cosmwasm, TargetKind.cosmwasm),
      (TargetId.ton, TargetKind.ton)] do
    expectMaterializePlanInvariantV1 "MapU8" target kind mapU8Compiled
      "Map state admits only Map UInt64 UInt64"
  expectMaterializePlanInvariantV1 "MapU8" TargetId.psy TargetKind.psy
    mapU8Compiled "Map state pilot requires UInt64 keys and values"
  for (target, kind) in #[
      (TargetId.quint, TargetKind.quint),
      (TargetId.soroban, TargetKind.soroban),
      (TargetId.openvm, TargetKind.openvm),
      (TargetId.icp, TargetKind.icp)] do
    expectMaterializePlanInvariantV1 "MapU8" target kind mapU8Compiled
      "only anonymous UInt64/Int64 widths are supported"

  -- MapI32: Map UInt64 Int32 state. All twelve stay named FC. Aleo/CW/
  -- TON fail on width / narrow-Int first, not MapInt/MapU32's
  -- Map-U64-U64. Int32-value ≠ Int64-value and ≠ UInt32-value. Not
  -- opening Map-of-Int32. MapU8 / MapInt / MapU32 / ArrI8 stay.
  let mapI32Source :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program MapI32 where\n" ++
    "  state m : Map UInt64 Int32\n\n" ++
    "  init() do\n" ++
    "    m := Map.empty()\n\n" ++
    "  entry put(k : UInt64, v : UInt64) : UInt64 do\n" ++
    "    return v\n\n" ++
    "end ProofForgeV2.Examples\n"
  let mapI32V1 ← match ← session.selectProgramV1 mapI32Source
      "<targets-map-i32>" "Examples.MapI32" none with
    | .ok v => pure v
    | .error e => throw <| IO.userError s!"MapI32 select: {e.render}"
  let mapI32Compiled ← liftResult <| Compiler.compileValidatedSourceV1 mapI32V1
  for (target, kind) in #[
      (TargetId.evm, TargetKind.evm),
      (TargetId.solana, TargetKind.solana)] do
    expectMaterializePlanInvariantV1 "MapI32" target kind mapI32Compiled
      "Map state value must be UInt64"
  for (target, kind) in #[
      (TargetId.near, TargetKind.near),
      (TargetId.noir, TargetKind.noir),
      (TargetId.aleo, TargetKind.aleo)] do
    expectMaterializePlanInvariantV1 "MapI32" target kind mapI32Compiled
      "Map state admits only Map UInt64 UInt64"
  expectMaterializePlanInvariantV1 "MapI32" TargetId.psy TargetKind.psy
    mapI32Compiled "Map state pilot requires UInt64 keys and values"
  expectMaterializePlanInvariantV1 "MapI32" TargetId.cosmwasm TargetKind.cosmwasm
    mapI32Compiled "Map state admits only Map UInt64 UInt64"
  expectMaterializePlanInvariantV1 "MapI32" TargetId.ton TargetKind.ton
    mapI32Compiled "Map state admits only Map UInt64 UInt64"
  for (target, kind) in #[
      (TargetId.quint, TargetKind.quint),
      (TargetId.soroban, TargetKind.soroban),
      (TargetId.openvm, TargetKind.openvm),
      (TargetId.icp, TargetKind.icp)] do
    expectMaterializePlanInvariantV1 "MapI32" target kind mapI32Compiled
      "only anonymous UInt64/Int64 widths are supported"

  -- MapI32Key: Map Int32 UInt64 state (signed 32-bit KEY). EVM/Solana
  -- stay on key-shape, not MapI32's value needle. Aleo/CW/TON fail on
  -- width / narrow-Int first, not MapIntKey's Map-U64-U64. Int32-key ≠
  -- Int32-value and ≠ Int64-key. Not opening Int32-key Map. MapI32 /
  -- MapIntKey / MapU32Key / OptI16 stay.
  let mapI32KeySource :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program MapI32Key where\n" ++
    "  state m : Map Int32 UInt64\n\n" ++
    "  init() do\n" ++
    "    m := Map.empty()\n\n" ++
    "  entry put(k : UInt64, v : UInt64) : UInt64 do\n" ++
    "    return v\n\n" ++
    "end ProofForgeV2.Examples\n"
  let mapI32KeyV1 ← match ← session.selectProgramV1 mapI32KeySource
      "<targets-map-i32-key>" "Examples.MapI32Key" none with
    | .ok v => pure v
    | .error e => throw <| IO.userError s!"MapI32Key select: {e.render}"
  let mapI32KeyCompiled ← liftResult <| Compiler.compileValidatedSourceV1 mapI32KeyV1
  for (target, kind) in #[
      (TargetId.evm, TargetKind.evm),
      (TargetId.solana, TargetKind.solana)] do
    expectMaterializePlanInvariantV1 "MapI32Key" target kind mapI32KeyCompiled
      "Map state admits only Map UInt64 UInt64 or Map Principal UInt64"
  for (target, kind) in #[
      (TargetId.near, TargetKind.near),
      (TargetId.noir, TargetKind.noir),
      (TargetId.aleo, TargetKind.aleo)] do
    expectMaterializePlanInvariantV1 "MapI32Key" target kind mapI32KeyCompiled
      "Map state admits only Map UInt64 UInt64"
  expectMaterializePlanInvariantV1 "MapI32Key" TargetId.psy TargetKind.psy
    mapI32KeyCompiled "Map state pilot requires UInt64 keys and values"
  expectMaterializePlanInvariantV1 "MapI32Key" TargetId.cosmwasm TargetKind.cosmwasm
    mapI32KeyCompiled "Map state admits only Map UInt64 UInt64"
  expectMaterializePlanInvariantV1 "MapI32Key" TargetId.ton TargetKind.ton
    mapI32KeyCompiled "Map state admits only Map UInt64 UInt64"
  for (target, kind) in #[
      (TargetId.quint, TargetKind.quint),
      (TargetId.soroban, TargetKind.soroban),
      (TargetId.openvm, TargetKind.openvm),
      (TargetId.icp, TargetKind.icp)] do
    expectMaterializePlanInvariantV1 "MapI32Key" target kind mapI32KeyCompiled
      "only anonymous UInt64/Int64 widths are supported"

set_option maxRecDepth 10000 in
unsafe def runRemainingNeedles : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  -- BytesBox: Bytes 4 state. Eight materializers admit; Quint/Soroban/
  -- ICP/OpenVM stay envelope FC. Not opening Bytes on those four.
  -- State only — no Bytes return ABI. Files-nonempty or named decline.
  let bytesBoxSource :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program BytesBox where\n" ++
    "  state b : Bytes 4\n\n" ++
    "  init() do\n" ++
    "    b[0] := 0\n\n" ++
    "  entry set0(v : UInt64) : UInt64 do\n" ++
    "    b[0] := 0\n" ++
    "    return v\n\n" ++
    "end ProofForgeV2.Examples\n"
  let bytesV1 ← match ← session.selectProgramV1 bytesBoxSource
      "<targets-bytes-box>" "Examples.BytesBox" none with
    | .ok v => pure v
    | .error e => throw <| IO.userError s!"BytesBox select: {e.render}"
  let bytesCompiled ← liftResult <| Compiler.compileValidatedSourceV1 bytesV1
  for target in [TargetId.evm, TargetId.solana, TargetId.near, TargetId.noir,
      TargetId.psy, TargetId.aleo, TargetId.cosmwasm, TargetId.ton] do
    let out ← liftResult <| materializeSelected target bytesCompiled
    expect (!(MaterializedArtifactsV1.filesOf out).isEmpty)
      s!"BytesBox: {target} must materialize Bytes 4"
  for target in [TargetId.quint, TargetId.soroban, TargetId.icp, TargetId.openvm] do
    match materializeSelected target bytesCompiled with
    | .ok _ =>
        throw <| IO.userError s!"BytesBox: {target} must decline Bytes state"
    | .error e =>
        expect ((e.render).contains "Bytes" ||
            (e.render).contains "container" ||
            (e.render).contains "anonymous" ||
            (e.render).contains "unsupported" ||
            (e.render).contains "pilot")
          s!"BytesBox {target} message must cite Bytes/container boundary, got {e.render}"

  -- BytesRetBox: Bytes 4 view-return. NEAR/Psy/CW admit. EVM/Solana/Noir/
  -- Aleo/TON named B-RET FC; Quint/Soroban/OpenVM/ICP stay container-state
  -- pilot FC. Not opening Bytes return ABI. Files-nonempty or named needles.
  let bytesRetBoxSource :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program BytesRetBox where\n" ++
    "  state b : Bytes 4\n\n" ++
    "  init() do\n" ++
    "    b[0] := 0\n\n" ++
    "  view get() : Bytes 4 do\n" ++
    "    return b\n\n" ++
    "end ProofForgeV2.Examples\n"
  let bytesRetV1 ← match ← session.selectProgramV1 bytesRetBoxSource
      "<targets-bytes-ret>" "Examples.BytesRetBox" none with
    | .ok v => pure v
    | .error e => throw <| IO.userError s!"BytesRetBox select: {e.render}"
  let bytesRetCompiled ← liftResult <| Compiler.compileValidatedSourceV1 bytesRetV1
  for target in [TargetId.near, TargetId.psy, TargetId.cosmwasm] do
    let out ← liftResult <| materializeSelected target bytesRetCompiled
    expect (!(MaterializedArtifactsV1.filesOf out).isEmpty)
      s!"BytesRetBox: {target} must materialize Bytes 4 return"
  expectMaterializePlanInvariantV1 "BytesRetBox" TargetId.evm TargetKind.evm
    bytesRetCompiled "cannot return Bytes"
  expectMaterializePlanInvariantV1 "BytesRetBox" TargetId.solana TargetKind.solana
    bytesRetCompiled "cannot return anonymous Bytes"
  expectMaterializePlanInvariantV1 "BytesRetBox" TargetId.noir TargetKind.noir
    bytesRetCompiled "anonymous Bytes return is outside the Noir B-RET ABI"
  expectMaterializePlanInvariantV1 "BytesRetBox" TargetId.aleo TargetKind.aleo
    bytesRetCompiled "aggregate return leaves must be UInt64/Int64"
  expectMaterializePlanInvariantV1 "BytesRetBox" TargetId.ton TargetKind.ton
    bytesRetCompiled "anonymous Bytes return is outside the Ton B-RET ABI"
  for (target, kind) in #[
      (TargetId.quint, TargetKind.quint),
      (TargetId.soroban, TargetKind.soroban),
      (TargetId.openvm, TargetKind.openvm),
      (TargetId.icp, TargetKind.icp)] do
    expectMaterializePlanInvariantV1 "BytesRetBox" target kind bytesRetCompiled
      "anonymous Bytes is outside the current container-state pilot"

  -- N-A4: Option state Normalize-admitted. Eleven materializers admit
  -- Option UInt64 state (Enum-shaped 2-leaf / tag+payload layout):
  -- EVM (BL-31), NEAR (BL-30), Solana (BL-29), Aleo (BL-35), CosmWasm
  -- (BL-33), Psy (BL-36), Noir (BL-32), TON (BL-34), plus envelope
  -- Quint/Soroban/OpenVM flatten. ICP stays Option-pilot (no Candid opt).
  let optionStateSource :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program OptBox where\n" ++
    "  state o : Option UInt64\n\n" ++
    "  init() do\n" ++
    "    o := Option.none()\n\n" ++
    "  entry setSome(v : UInt64) : UInt64 do\n" ++
    "    o := Option.some(v)\n" ++
    "    return v\n\n" ++
    "end ProofForgeV2.Examples\n"
  let optV1 ← match ← session.selectProgramV1 optionStateSource
      "<targets-option-state>" "Examples.OptBox" none with
    | .ok v => pure v
    | .error e => throw <| IO.userError s!"N-A4 Option select: {e.render}"
  let optCompiled ← liftResult <| Compiler.compileValidatedSourceV1 optV1
  -- EVM/NEAR/Solana/Aleo admit Option UInt64 state.
  let _ ← liftResult <| materializeSelected TargetId.evm optCompiled
  let _ ← liftResult <| materializeSelected TargetId.near optCompiled
  let _ ← liftResult <| materializeSelected TargetId.solana optCompiled
  let _ ← liftResult <| materializeSelected TargetId.aleo optCompiled
  -- CosmWasm admits Option UInt64 state (BL-33).
  let _ ← liftResult <| materializeSelected TargetId.cosmwasm optCompiled
  -- Psy admits Option UInt64 state (BL-36).
  let _ ← liftResult <| materializeSelected TargetId.psy optCompiled
  -- Noir admits Option UInt64 state (BL-32).
  let _ ← liftResult <| materializeSelected TargetId.noir optCompiled
  -- TON admits Option UInt64 state (BL-34).
  let _ ← liftResult <| materializeSelected TargetId.ton optCompiled
  -- Envelope-4 Option wave: Quint/Soroban/OpenVM flatten to tag+payload.
  -- ICP stays Option-pilot (no Candid opt).
  for target in [TargetId.quint, TargetId.soroban, TargetId.openvm] do
    let out ← liftResult <| materializeSelected target optCompiled
    expect (!(MaterializedArtifactsV1.filesOf out).isEmpty)
      s!"N-A4 Option: {target} must materialize Option UInt64 state"
  match materializeSelected TargetId.icp optCompiled with
  | .ok _ =>
      throw <| IO.userError "N-A4 Option: icp must decline Option state"
  | .error e =>
      expect ((e.render).contains "Option" ||
          (e.render).contains "unsupported" ||
          (e.render).contains "pilot" ||
          (e.render).contains "public" ||
          (e.render).contains "container" ||
          (e.render).contains "anonymous")
        s!"N-A4 Option icp message must cite Option/container boundary, got {e.render}"

  -- OptRetBox: Option UInt64 *entry* return. Seven materializers admit.
  -- TON view-only B-RET FC; Quint/Soroban/OpenVM name Q0/S0/O0 return.
  -- ICP stays Option-pilot. Entry peek, not view (TON view-only B-RET
  -- would conflate). Not opening Option return. OptBox state pin stays.
  let optRetSource :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program OptRetBox where\n" ++
    "  state o : Option UInt64\n\n" ++
    "  init() do\n" ++
    "    o := Option.none()\n\n" ++
    "  entry peek() : Option UInt64 do\n" ++
    "    return o\n\n" ++
    "end ProofForgeV2.Examples\n"
  let optRetV1 ← match ← session.selectProgramV1 optRetSource
      "<targets-opt-ret>" "Examples.OptRetBox" none with
    | .ok v => pure v
    | .error e => throw <| IO.userError s!"OptRetBox select: {e.render}"
  let optRetCompiled ← liftResult <| Compiler.compileValidatedSourceV1 optRetV1
  for target in [TargetId.evm, TargetId.solana, TargetId.near, TargetId.noir,
      TargetId.aleo, TargetId.psy, TargetId.cosmwasm] do
    let out ← liftResult <| materializeSelected target optRetCompiled
    expect (!(MaterializedArtifactsV1.filesOf out).isEmpty)
      s!"OptRetBox: {target} must materialize Option UInt64 entry return"
  expectMaterializePlanInvariantV1 "OptRetBox" TargetId.ton TargetKind.ton
    optRetCompiled "entry 'peek' cannot return multi-leaf aggregate"
  expectMaterializePlanInvariantV1 "OptRetBox" TargetId.quint TargetKind.quint
    optRetCompiled "Option return is outside Q0"
  expectMaterializePlanInvariantV1 "OptRetBox" TargetId.soroban TargetKind.soroban
    optRetCompiled "Option return is outside S0"
  expectMaterializePlanInvariantV1 "OptRetBox" TargetId.openvm TargetKind.openvm
    optRetCompiled "Option return is outside O0"
  expectMaterializePlanInvariantV1 "OptRetBox" TargetId.icp TargetKind.icp
    optRetCompiled "anonymous Option is outside the current container-state pilot"

  -- OptViewRet: Option UInt64 *view* return. Distinct from OptRetBox
  -- entry: TON view-only B-RET admits; Aleo query-descriptor admit
  -- (`kind=computed`, not Final). Quint/Soroban/OpenVM name Q0/S0/O0
  -- return. ICP stays Option-pilot. OptBox / OptRetBox / NestOpt stay.
  let optViewRetSource :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program OptViewRet where\n" ++
    "  state o : Option UInt64\n\n" ++
    "  init() do\n" ++
    "    o := Option.none()\n\n" ++
    "  view peek() : Option UInt64 do\n" ++
    "    return o\n\n" ++
    "end ProofForgeV2.Examples\n"
  let optViewRetV1 ← match ← session.selectProgramV1 optViewRetSource
      "<targets-opt-view-ret>" "Examples.OptViewRet" none with
    | .ok v => pure v
    | .error e => throw <| IO.userError s!"OptViewRet select: {e.render}"
  let optViewRetCompiled ← liftResult <| Compiler.compileValidatedSourceV1 optViewRetV1
  for target in [TargetId.evm, TargetId.solana, TargetId.near, TargetId.noir,
      TargetId.aleo, TargetId.psy, TargetId.cosmwasm, TargetId.ton] do
    let out ← liftResult <| materializeSelected target optViewRetCompiled
    expect (!(MaterializedArtifactsV1.filesOf out).isEmpty)
      s!"OptViewRet: {target} must materialize Option UInt64 view return"
  expectMaterializePlanInvariantV1 "OptViewRet" TargetId.quint TargetKind.quint
    optViewRetCompiled "Option return is outside Q0"
  expectMaterializePlanInvariantV1 "OptViewRet" TargetId.soroban TargetKind.soroban
    optViewRetCompiled "Option return is outside S0"
  expectMaterializePlanInvariantV1 "OptViewRet" TargetId.openvm TargetKind.openvm
    optViewRetCompiled "Option return is outside O0"
  expectMaterializePlanInvariantV1 "OptViewRet" TargetId.icp TargetKind.icp
    optViewRetCompiled "anonymous Option is outside the current container-state pilot"

  -- NestOpt: Option Option UInt64 state. All twelve targets stay named
  -- payload/pilot FC. Not opening nested Option. OptBox / OptRetBox stay.
  let nestOptSource :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program NestOpt where\n" ++
    "  state o : Option Option UInt64\n\n" ++
    "  init() do\n" ++
    "    o := Option.none()\n\n" ++
    "  entry setSome(v : UInt64) : UInt64 do\n" ++
    "    o := Option.some(Option.some(v))\n" ++
    "    return v\n\n" ++
    "end ProofForgeV2.Examples\n"
  let nestOptV1 ← match ← session.selectProgramV1 nestOptSource
      "<targets-nest-opt>" "Examples.NestOpt" none with
    | .ok v => pure v
    | .error e => throw <| IO.userError s!"NestOpt select: {e.render}"
  let nestOptCompiled ← liftResult <| Compiler.compileValidatedSourceV1 nestOptV1
  expectMaterializePlanInvariantV1 "NestOpt" TargetId.evm TargetKind.evm
    nestOptCompiled "Option state admits only UInt64 payload"
  expectMaterializePlanInvariantV1 "NestOpt" TargetId.solana TargetKind.solana
    nestOptCompiled "Option state 'o' element must be UInt64"
  for (target, kind) in #[
      (TargetId.near, TargetKind.near),
      (TargetId.noir, TargetKind.noir),
      (TargetId.aleo, TargetKind.aleo),
      (TargetId.psy, TargetKind.psy),
      (TargetId.cosmwasm, TargetKind.cosmwasm),
      (TargetId.ton, TargetKind.ton)] do
    expectMaterializePlanInvariantV1 "NestOpt" target kind nestOptCompiled
      "Option state 'o' requires UInt64 payload"
  -- Nested Option is a non-UInt64 payload after Option type admission.
  expectMaterializePlanInvariantV1 "NestOpt" TargetId.quint TargetKind.quint
    nestOptCompiled "Option element must be UInt64"
  expectMaterializePlanInvariantV1 "NestOpt" TargetId.soroban TargetKind.soroban
    nestOptCompiled "Option state 'o' requires UInt64 payload"
  expectMaterializePlanInvariantV1 "NestOpt" TargetId.openvm TargetKind.openvm
    nestOptCompiled "UInt64 payload"
  expectMaterializePlanInvariantV1 "NestOpt" TargetId.icp TargetKind.icp
    nestOptCompiled "anonymous Option is outside the current container-state pilot"

  -- OptArr: Option Array UInt64 2 state. All twelve targets stay named
  -- payload/pilot FC. Not opening Option-of-Array. NestOpt / OptBox /
  -- ArrayBox stay.
  let optArrSource :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program OptArr where\n" ++
    "  state o : Option Array UInt64 2\n\n" ++
    "  init() do\n" ++
    "    o := Option.none()\n\n" ++
    "  entry setSome(v : UInt64) : UInt64 do\n" ++
    "    return v\n\n" ++
    "end ProofForgeV2.Examples\n"
  let optArrV1 ← match ← session.selectProgramV1 optArrSource
      "<targets-opt-arr>" "Examples.OptArr" none with
    | .ok v => pure v
    | .error e => throw <| IO.userError s!"OptArr select: {e.render}"
  let optArrCompiled ← liftResult <| Compiler.compileValidatedSourceV1 optArrV1
  expectMaterializePlanInvariantV1 "OptArr" TargetId.evm TargetKind.evm
    optArrCompiled "Option state admits only UInt64 payload"
  expectMaterializePlanInvariantV1 "OptArr" TargetId.solana TargetKind.solana
    optArrCompiled "Option state 'o' element must be UInt64"
  for (target, kind) in #[
      (TargetId.near, TargetKind.near),
      (TargetId.noir, TargetKind.noir),
      (TargetId.aleo, TargetKind.aleo),
      (TargetId.psy, TargetKind.psy),
      (TargetId.cosmwasm, TargetKind.cosmwasm),
      (TargetId.ton, TargetKind.ton)] do
    expectMaterializePlanInvariantV1 "OptArr" target kind optArrCompiled
      "Option state 'o' requires UInt64 payload"
  expectMaterializePlanInvariantV1 "OptArr" TargetId.quint TargetKind.quint
    optArrCompiled "Option element must be UInt64"
  expectMaterializePlanInvariantV1 "OptArr" TargetId.soroban TargetKind.soroban
    optArrCompiled "Option state 'o' requires UInt64 payload"
  expectMaterializePlanInvariantV1 "OptArr" TargetId.openvm TargetKind.openvm
    optArrCompiled "UInt64 payload"
  expectMaterializePlanInvariantV1 "OptArr" TargetId.icp TargetKind.icp
    optArrCompiled "anonymous Option is outside the current container-state pilot"

  -- OptBytes: Option Bytes 4 state. All twelve targets stay named
  -- payload/pilot FC. Not opening Option-of-Bytes. OptArr / OptBox /
  -- BytesBox stay.
  let optBytesSource :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program OptBytes where\n" ++
    "  state o : Option Bytes 4\n\n" ++
    "  init() do\n" ++
    "    o := Option.none()\n\n" ++
    "  entry setSome(v : UInt64) : UInt64 do\n" ++
    "    return v\n\n" ++
    "end ProofForgeV2.Examples\n"
  let optBytesV1 ← match ← session.selectProgramV1 optBytesSource
      "<targets-opt-bytes>" "Examples.OptBytes" none with
    | .ok v => pure v
    | .error e => throw <| IO.userError s!"OptBytes select: {e.render}"
  let optBytesCompiled ← liftResult <| Compiler.compileValidatedSourceV1 optBytesV1
  expectMaterializePlanInvariantV1 "OptBytes" TargetId.evm TargetKind.evm
    optBytesCompiled "Option state admits only UInt64 payload"
  expectMaterializePlanInvariantV1 "OptBytes" TargetId.solana TargetKind.solana
    optBytesCompiled "Option state 'o' element must be UInt64"
  for (target, kind) in #[
      (TargetId.near, TargetKind.near),
      (TargetId.noir, TargetKind.noir),
      (TargetId.aleo, TargetKind.aleo),
      (TargetId.psy, TargetKind.psy),
      (TargetId.cosmwasm, TargetKind.cosmwasm),
      (TargetId.ton, TargetKind.ton)] do
    expectMaterializePlanInvariantV1 "OptBytes" target kind optBytesCompiled
      "Option state 'o' requires UInt64 payload"
  for (target, kind) in #[
      (TargetId.quint, TargetKind.quint),
      (TargetId.soroban, TargetKind.soroban),
      (TargetId.openvm, TargetKind.openvm),
      (TargetId.icp, TargetKind.icp)] do
    expectMaterializePlanInvariantV1 "OptBytes" target kind optBytesCompiled
      "anonymous Bytes is outside the current container-state pilot"

  -- OptMap: Option Map UInt64 UInt64 state. All twelve targets stay named
  -- payload/pilot FC. Not opening Option-of-Map. OptBytes / OptArr /
  -- MapMini stay.
  let optMapSource :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program OptMap where\n" ++
    "  state o : Option Map UInt64 UInt64\n\n" ++
    "  init() do\n" ++
    "    o := Option.none()\n\n" ++
    "  entry setSome(v : UInt64) : UInt64 do\n" ++
    "    return v\n\n" ++
    "end ProofForgeV2.Examples\n"
  let optMapV1 ← match ← session.selectProgramV1 optMapSource
      "<targets-opt-map>" "Examples.OptMap" none with
    | .ok v => pure v
    | .error e => throw <| IO.userError s!"OptMap select: {e.render}"
  let optMapCompiled ← liftResult <| Compiler.compileValidatedSourceV1 optMapV1
  expectMaterializePlanInvariantV1 "OptMap" TargetId.evm TargetKind.evm
    optMapCompiled "Option state admits only UInt64 payload"
  expectMaterializePlanInvariantV1 "OptMap" TargetId.solana TargetKind.solana
    optMapCompiled "Option state 'o' element must be UInt64"
  for (target, kind) in #[
      (TargetId.near, TargetKind.near),
      (TargetId.noir, TargetKind.noir),
      (TargetId.aleo, TargetKind.aleo),
      (TargetId.psy, TargetKind.psy),
      (TargetId.cosmwasm, TargetKind.cosmwasm),
      (TargetId.ton, TargetKind.ton)] do
    expectMaterializePlanInvariantV1 "OptMap" target kind optMapCompiled
      "Option state 'o' requires UInt64 payload"
  expectMaterializePlanInvariantV1 "OptMap" TargetId.quint TargetKind.quint
    optMapCompiled "Option element must be UInt64"
  expectMaterializePlanInvariantV1 "OptMap" TargetId.soroban TargetKind.soroban
    optMapCompiled "Option state 'o' requires UInt64 payload"
  expectMaterializePlanInvariantV1 "OptMap" TargetId.openvm TargetKind.openvm
    optMapCompiled "UInt64 payload"
  expectMaterializePlanInvariantV1 "OptMap" TargetId.icp TargetKind.icp
    optMapCompiled "anonymous Map is outside the current container-state pilot"

  -- OptPrin: Option Principal state. All twelve targets stay named
  -- payload/Principal FC. Aleo/TON/Soroban/OpenVM/ICP use Principal-named
  -- needles, distinct from NestOpt payload/pilot. Not opening
  -- Option-of-Principal. OptMap / OptBox / PrincipalMix stay.
  let optPrinSource :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program OptPrin where\n" ++
    "  state o : Option Principal\n\n" ++
    "  init() do\n" ++
    "    o := Option.none()\n\n" ++
    "  entry setSome(v : UInt64) : UInt64 do\n" ++
    "    return v\n\n" ++
    "end ProofForgeV2.Examples\n"
  let optPrinV1 ← match ← session.selectProgramV1 optPrinSource
      "<targets-opt-prin>" "Examples.OptPrin" none with
    | .ok v => pure v
    | .error e => throw <| IO.userError s!"OptPrin select: {e.render}"
  let optPrinCompiled ← liftResult <| Compiler.compileValidatedSourceV1 optPrinV1
  expectMaterializePlanInvariantV1 "OptPrin" TargetId.evm TargetKind.evm
    optPrinCompiled "Option state admits only UInt64 payload"
  expectMaterializePlanInvariantV1 "OptPrin" TargetId.solana TargetKind.solana
    optPrinCompiled "Option state 'o' element must be UInt64"
  for (target, kind) in #[
      (TargetId.near, TargetKind.near),
      (TargetId.noir, TargetKind.noir),
      (TargetId.psy, TargetKind.psy),
      (TargetId.cosmwasm, TargetKind.cosmwasm)] do
    expectMaterializePlanInvariantV1 "OptPrin" target kind optPrinCompiled
      "Option state 'o' requires UInt64 payload"
  expectMaterializePlanInvariantV1 "OptPrin" TargetId.aleo TargetKind.aleo
    optPrinCompiled "Principal/String stay fail-closed"
  expectMaterializePlanInvariantV1 "OptPrin" TargetId.quint TargetKind.quint
    optPrinCompiled "Option element must be UInt64"
  expectMaterializePlanInvariantV1 "OptPrin" TargetId.ton TargetKind.ton
    optPrinCompiled "no Field/Principal"
  for (target, kind) in #[
      (TargetId.soroban, TargetKind.soroban),
      (TargetId.openvm, TargetKind.openvm)] do
    expectMaterializePlanInvariantV1 "OptPrin" target kind optPrinCompiled
      "Principal/aggregates/Bytes"
  expectMaterializePlanInvariantV1 "OptPrin" TargetId.icp TargetKind.icp
    optPrinCompiled "Principal/aggregates/Map/Option/Bytes/String fail closed"

  -- OptField: Option Field bn254_fr state. All twelve targets stay named
  -- payload/Field FC. Not opening Option-of-Field. OptPrin / OptBox /
  -- FieldMix stay.
  let optFieldSource :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program OptField where\n" ++
    "  state o : Option Field bn254_fr\n\n" ++
    "  init() do\n" ++
    "    o := Option.none()\n\n" ++
    "  entry setSome(v : UInt64) : UInt64 do\n" ++
    "    return v\n\n" ++
    "end ProofForgeV2.Examples\n"
  let optFieldV1 ← match ← session.selectProgramV1 optFieldSource
      "<targets-opt-field>" "Examples.OptField" none with
    | .ok v => pure v
    | .error e => throw <| IO.userError s!"OptField select: {e.render}"
  let optFieldCompiled ← liftResult <| Compiler.compileValidatedSourceV1 optFieldV1
  expectMaterializePlanInvariantV1 "OptField" TargetId.evm TargetKind.evm
    optFieldCompiled "Option state admits only UInt64 payload"
  for (target, kind) in #[
      (TargetId.solana, TargetKind.solana),
      (TargetId.near, TargetKind.near)] do
    expectMaterializePlanInvariantV1 "OptField" target kind optFieldCompiled
      "no native Field"
  expectMaterializePlanInvariantV1 "OptField" TargetId.noir TargetKind.noir
    optFieldCompiled "Option state 'o' requires UInt64 payload"
  expectMaterializePlanInvariantV1 "OptField" TargetId.aleo TargetKind.aleo
    optFieldCompiled "bn254 Fr and Goldilocks fail closed as wrong modulus"
  expectMaterializePlanInvariantV1 "OptField" TargetId.psy TargetKind.psy
    optFieldCompiled "bn254 Fr and BLS12-377 Fr fail closed as wrong modulus"
  expectMaterializePlanInvariantV1 "OptField" TargetId.quint TargetKind.quint
    optFieldCompiled "narrow Int/Field/aggregates/Bytes fail closed"
  expectMaterializePlanInvariantV1 "OptField" TargetId.cosmwasm TargetKind.cosmwasm
    optFieldCompiled "no Field"
  expectMaterializePlanInvariantV1 "OptField" TargetId.ton TargetKind.ton
    optFieldCompiled "no Field/Principal"
  for (target, kind) in #[
      (TargetId.soroban, TargetKind.soroban),
      (TargetId.openvm, TargetKind.openvm)] do
    expectMaterializePlanInvariantV1 "OptField" target kind optFieldCompiled
      "Int/Field/Principal/aggregates/Bytes"
  expectMaterializePlanInvariantV1 "OptField" TargetId.icp TargetKind.icp
    optFieldCompiled "Int/Field/Principal/aggregates/Map/Option/Bytes/String fail closed"

  -- OptStr: Option String state. All twelve stay named payload/String FC.
  -- Not opening Option-of-String. OptField / OptBox /
  -- StringInterfaceBoundary stay.
  let optStrSource :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program OptStr where\n" ++
    "  state o : Option String\n\n" ++
    "  init() do\n" ++
    "    o := Option.none()\n\n" ++
    "  entry setSome(v : UInt64) : UInt64 do\n" ++
    "    return v\n\n" ++
    "end ProofForgeV2.Examples\n"
  let optStrV1 ← match ← session.selectProgramV1 optStrSource
      "<targets-opt-str>" "Examples.OptStr" none with
    | .ok v => pure v
    | .error e => throw <| IO.userError s!"OptStr select: {e.render}"
  let optStrCompiled ← liftResult <| Compiler.compileValidatedSourceV1 optStrV1
  expectMaterializePlanInvariantV1 "OptStr" TargetId.evm TargetKind.evm
    optStrCompiled "Option state admits only UInt64 payload"
  expectMaterializePlanInvariantV1 "OptStr" TargetId.solana TargetKind.solana
    optStrCompiled "not a fixed 32-byte pubkey"
  expectMaterializePlanInvariantV1 "OptStr" TargetId.near TargetKind.near
    optStrCompiled "not a NEAR account-id string"
  expectMaterializePlanInvariantV1 "OptStr" TargetId.noir TargetKind.noir
    optStrCompiled "not a Field element"
  expectMaterializePlanInvariantV1 "OptStr" TargetId.aleo TargetKind.aleo
    optStrCompiled "Principal/String stay fail-closed"
  expectMaterializePlanInvariantV1 "OptStr" TargetId.psy TargetKind.psy
    optStrCompiled "Option state 'o' requires UInt64 payload"
  expectMaterializePlanInvariantV1 "OptStr" TargetId.quint TargetKind.quint
    optStrCompiled "narrow Int/Field/aggregates/Bytes fail closed"
  expectMaterializePlanInvariantV1 "OptStr" TargetId.cosmwasm TargetKind.cosmwasm
    optStrCompiled "no Field"
  expectMaterializePlanInvariantV1 "OptStr" TargetId.ton TargetKind.ton
    optStrCompiled "no Field/Principal"
  for (target, kind) in #[
      (TargetId.soroban, TargetKind.soroban),
      (TargetId.openvm, TargetKind.openvm)] do
    expectMaterializePlanInvariantV1 "OptStr" target kind optStrCompiled
      "Int/Field/Principal/aggregates/Bytes"
  expectMaterializePlanInvariantV1 "OptStr" TargetId.icp TargetKind.icp
    optStrCompiled "Map/Option/Bytes/String fail closed"

  -- OptBool: Option Bool state. Eight targets stay named payload FC.
  -- Quint/Soroban/OpenVM admit Option type so they fail on payload.
  -- ICP stays Option-pilot. Not opening Option-of-Bool. OptStr / OptBox /
  -- BoolPredicate / ArrBool stay.
  let optBoolSource :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program OptBool where\n" ++
    "  state o : Option Bool\n\n" ++
    "  init() do\n" ++
    "    o := Option.none()\n\n" ++
    "  entry setSome(v : UInt64) : UInt64 do\n" ++
    "    o := Option.some(false)\n" ++
    "    return v\n\n" ++
    "end ProofForgeV2.Examples\n"
  let optBoolV1 ← match ← session.selectProgramV1 optBoolSource
      "<targets-opt-bool>" "Examples.OptBool" none with
    | .ok v => pure v
    | .error e => throw <| IO.userError s!"OptBool select: {e.render}"
  let optBoolCompiled ← liftResult <| Compiler.compileValidatedSourceV1 optBoolV1
  expectMaterializePlanInvariantV1 "OptBool" TargetId.evm TargetKind.evm
    optBoolCompiled "Option state admits only UInt64 payload"
  expectMaterializePlanInvariantV1 "OptBool" TargetId.solana TargetKind.solana
    optBoolCompiled "Option state 'o' element must be UInt64"
  for (target, kind) in #[
      (TargetId.near, TargetKind.near),
      (TargetId.noir, TargetKind.noir),
      (TargetId.aleo, TargetKind.aleo),
      (TargetId.psy, TargetKind.psy),
      (TargetId.cosmwasm, TargetKind.cosmwasm),
      (TargetId.ton, TargetKind.ton)] do
    expectMaterializePlanInvariantV1 "OptBool" target kind optBoolCompiled
      "Option state 'o' requires UInt64 payload"
  expectMaterializePlanInvariantV1 "OptBool" TargetId.quint TargetKind.quint
    optBoolCompiled "Option element must be UInt64"
  expectMaterializePlanInvariantV1 "OptBool" TargetId.soroban TargetKind.soroban
    optBoolCompiled "Option state 'o' requires UInt64 payload"
  expectMaterializePlanInvariantV1 "OptBool" TargetId.openvm TargetKind.openvm
    optBoolCompiled "UInt64 payload"
  expectMaterializePlanInvariantV1 "OptBool" TargetId.icp TargetKind.icp
    optBoolCompiled "anonymous Option is outside the current container-state pilot"

  -- OptInt: Option Int64 state. EVM/Solana/NEAR/Noir/Aleo/Psy/CW admit
  -- unsigned tag + signed payload. TON admits tag uint64 + signed int64
  -- cells. Envelope-4 stay named FC on this mixed UInt64-param program.
  -- ICP stays Option-pilot. Not opening Option-of-Int8 or Option-of-UInt128.
  let optIntSource :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program OptInt where\n" ++
    "  state o : Option Int64\n\n" ++
    "  init() do\n" ++
    "    o := Option.none()\n\n" ++
    "  entry setSome(v : UInt64) : UInt64 do\n" ++
    "    o := Option.some(0)\n" ++
    "    return v\n\n" ++
    "end ProofForgeV2.Examples\n"
  let optIntV1 ← match ← session.selectProgramV1 optIntSource
      "<targets-opt-int>" "Examples.OptInt" none with
    | .ok v => pure v
    | .error e => throw <| IO.userError s!"OptInt select: {e.render}"
  let optIntCompiled ← liftResult <| Compiler.compileValidatedSourceV1 optIntV1
  let optIntEvmOut ← liftResult <| materializeSelected TargetId.evm optIntCompiled
  expect (!(MaterializedArtifactsV1.filesOf optIntEvmOut).isEmpty)
    "OptInt: evm must materialize Option Int64"
  let optIntSolOut ← liftResult <| materializeSelected TargetId.solana optIntCompiled
  expect (!(MaterializedArtifactsV1.filesOf optIntSolOut).isEmpty)
    "OptInt: solana must materialize Option Int64"
  let optIntOut ← liftResult <| materializeSelected TargetId.cosmwasm optIntCompiled
  expect (!(MaterializedArtifactsV1.filesOf optIntOut).isEmpty)
    "OptInt: cosmwasm must materialize Option Int64"
  let optIntTonOut ← liftResult <| materializeSelected TargetId.ton optIntCompiled
  expect (!(MaterializedArtifactsV1.filesOf optIntTonOut).isEmpty)
    "OptInt: ton must materialize Option Int64"
  let optIntNearOut ← liftResult <| materializeSelected TargetId.near optIntCompiled
  expect (!(MaterializedArtifactsV1.filesOf optIntNearOut).isEmpty)
    "OptInt: near must materialize Option Int64"
  let optIntNoirOut ← liftResult <| materializeSelected TargetId.noir optIntCompiled
  expect (!(MaterializedArtifactsV1.filesOf optIntNoirOut).isEmpty)
    "OptInt: noir must materialize Option Int64"
  let optIntAleoOut ← liftResult <| materializeSelected TargetId.aleo optIntCompiled
  expect (!(MaterializedArtifactsV1.filesOf optIntAleoOut).isEmpty)
    "OptInt: aleo must materialize Option Int64"
  let optIntPsyOut ← liftResult <| materializeSelected TargetId.psy optIntCompiled
  expect (!(MaterializedArtifactsV1.filesOf optIntPsyOut).isEmpty)
    "OptInt: psy must materialize Option Int64"
  expectMaterializePlanInvariantV1 "OptInt" TargetId.quint TargetKind.quint
    optIntCompiled "Option element must be UInt64"
  expectMaterializePlanInvariantV1 "OptInt" TargetId.soroban TargetKind.soroban
    optIntCompiled "Option state 'o' requires UInt64 payload"
  expectMaterializePlanInvariantV1 "OptInt" TargetId.openvm TargetKind.openvm
    optIntCompiled "UInt64 payload"
  expectMaterializePlanInvariantV1 "OptInt" TargetId.icp TargetKind.icp
    optIntCompiled "anonymous Option is outside the current container-state pilot"

  -- OptU128: Option UInt128 state. TON admits as tag uint64 + one
  -- uint128 payload cell (not CosmWasm 2-limb). Other eleven stay
  -- named FC. Aleo shares the Option-payload needle (UInt128 width
  -- is admitted). Quint/Soroban/OpenVM/ICP stay on the UInt64 width
  -- needle. Not opening Option-of-UInt128 on the eleven.
  let optU128Source :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program OptU128 where\n" ++
    "  state o : Option UInt128\n\n" ++
    "  init() do\n" ++
    "    o := Option.none()\n\n" ++
    "  entry setSome(v : UInt64) : UInt64 do\n" ++
    "    o := Option.some(0)\n" ++
    "    return v\n\n" ++
    "end ProofForgeV2.Examples\n"
  let optU128V1 ← match ← session.selectProgramV1 optU128Source
      "<targets-opt-u128>" "Examples.OptU128" none with
    | .ok v => pure v
    | .error e => throw <| IO.userError s!"OptU128 select: {e.render}"
  let optU128Compiled ← liftResult <| Compiler.compileValidatedSourceV1 optU128V1
  expectMaterializePlanInvariantV1 "OptU128" TargetId.evm TargetKind.evm
    optU128Compiled "Option state admits only UInt64 payload"
  expectMaterializePlanInvariantV1 "OptU128" TargetId.solana TargetKind.solana
    optU128Compiled "Option state 'o' element must be UInt64"
  for (target, kind) in #[
      (TargetId.near, TargetKind.near),
      (TargetId.noir, TargetKind.noir),
      (TargetId.psy, TargetKind.psy),
      (TargetId.cosmwasm, TargetKind.cosmwasm),
      (TargetId.aleo, TargetKind.aleo)] do
    expectMaterializePlanInvariantV1 "OptU128" target kind optU128Compiled
      "Option state 'o' requires UInt64 payload"
  let optU128TonOut ← liftResult <| materializeSelected TargetId.ton optU128Compiled
  expect (!(MaterializedArtifactsV1.filesOf optU128TonOut).isEmpty)
    "OptU128: ton must materialize Option UInt128"
  for (target, kind) in #[
      (TargetId.quint, TargetKind.quint),
      (TargetId.soroban, TargetKind.soroban),
      (TargetId.openvm, TargetKind.openvm),
      (TargetId.icp, TargetKind.icp)] do
    expectMaterializePlanInvariantV1 "OptU128" target kind optU128Compiled
      "only anonymous UInt64/Int64 widths are supported"

  -- OptU256: Option UInt256 state. Same twelve named-FC needles as
  -- OptU128, but UInt256 ≠ UInt128 so it is its own pin. Aleo stays on
  -- width; TON now uses Option-UInt64-payload (bare UInt256 is
  -- admitted). Quint/Soroban/OpenVM/ICP stay on the UInt64 width
  -- needle, not OptBool's Option-pilot. Not opening Option-of-UInt256.
  -- OptU128 / OptInt / OptBool / MapU256 / ArrU256 stay.
  let optU256Source :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program OptU256 where\n" ++
    "  state o : Option UInt256\n\n" ++
    "  init() do\n" ++
    "    o := Option.none()\n\n" ++
    "  entry setSome(v : UInt64) : UInt64 do\n" ++
    "    o := Option.some(0)\n" ++
    "    return v\n\n" ++
    "end ProofForgeV2.Examples\n"
  let optU256V1 ← match ← session.selectProgramV1 optU256Source
      "<targets-opt-u256>" "Examples.OptU256" none with
    | .ok v => pure v
    | .error e => throw <| IO.userError s!"OptU256 select: {e.render}"
  let optU256Compiled ← liftResult <| Compiler.compileValidatedSourceV1 optU256V1
  expectMaterializePlanInvariantV1 "OptU256" TargetId.evm TargetKind.evm
    optU256Compiled "Option state admits only UInt64 payload"
  expectMaterializePlanInvariantV1 "OptU256" TargetId.solana TargetKind.solana
    optU256Compiled "Option state 'o' element must be UInt64"
  for (target, kind) in #[
      (TargetId.near, TargetKind.near),
      (TargetId.noir, TargetKind.noir),
      (TargetId.psy, TargetKind.psy),
      (TargetId.cosmwasm, TargetKind.cosmwasm)] do
    expectMaterializePlanInvariantV1 "OptU256" target kind optU256Compiled
      "Option state 'o' requires UInt64 payload"
  expectMaterializePlanInvariantV1 "OptU256" TargetId.aleo TargetKind.aleo
    optU256Compiled "only anonymous UInt64/UInt32/UInt16/UInt8/UInt128/Int64/Int32/Int16/Int8 widths are supported"
  expectMaterializePlanInvariantV1 "OptU256" TargetId.ton TargetKind.ton
    optU256Compiled "Option state 'o' requires UInt64 payload"
  for (target, kind) in #[
      (TargetId.quint, TargetKind.quint),
      (TargetId.soroban, TargetKind.soroban),
      (TargetId.openvm, TargetKind.openvm),
      (TargetId.icp, TargetKind.icp)] do
    expectMaterializePlanInvariantV1 "OptU256" target kind optU256Compiled
      "only anonymous UInt64/Int64 widths are supported"

  -- OptU32: Option UInt32 state. UInt32 is a legal Aleo/TON width, so
  -- those two stay on Option-payload, not OptU128's width needles.
  -- Envelope-4 intern UInt32 as an Array-index width, so Quint/Soroban/
  -- OpenVM fail on Option payload (not width). ICP stays Option-pilot.
  -- Not opening Option-of-UInt32. OptU256 / OptU128 / OptInt / ArrU8 stay.
  let optU32Source :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program OptU32 where\n" ++
    "  state o : Option UInt32\n\n" ++
    "  init() do\n" ++
    "    o := Option.none()\n\n" ++
    "  entry setSome(v : UInt64) : UInt64 do\n" ++
    "    o := Option.some(0)\n" ++
    "    return v\n\n" ++
    "end ProofForgeV2.Examples\n"
  let optU32V1 ← match ← session.selectProgramV1 optU32Source
      "<targets-opt-u32>" "Examples.OptU32" none with
    | .ok v => pure v
    | .error e => throw <| IO.userError s!"OptU32 select: {e.render}"
  let optU32Compiled ← liftResult <| Compiler.compileValidatedSourceV1 optU32V1
  expectMaterializePlanInvariantV1 "OptU32" TargetId.evm TargetKind.evm
    optU32Compiled "Option state admits only UInt64 payload"
  expectMaterializePlanInvariantV1 "OptU32" TargetId.solana TargetKind.solana
    optU32Compiled "Option state 'o' element must be UInt64"
  for (target, kind) in #[
      (TargetId.near, TargetKind.near),
      (TargetId.noir, TargetKind.noir),
      (TargetId.aleo, TargetKind.aleo),
      (TargetId.psy, TargetKind.psy),
      (TargetId.cosmwasm, TargetKind.cosmwasm),
      (TargetId.ton, TargetKind.ton)] do
    expectMaterializePlanInvariantV1 "OptU32" target kind optU32Compiled
      "Option state 'o' requires UInt64 payload"
  expectMaterializePlanInvariantV1 "OptU32" TargetId.quint TargetKind.quint
    optU32Compiled "Option element must be UInt64"
  expectMaterializePlanInvariantV1 "OptU32" TargetId.soroban TargetKind.soroban
    optU32Compiled "Option state 'o' requires UInt64 payload"
  expectMaterializePlanInvariantV1 "OptU32" TargetId.openvm TargetKind.openvm
    optU32Compiled "UInt64 payload"
  expectMaterializePlanInvariantV1 "OptU32" TargetId.icp TargetKind.icp
    optU32Compiled "anonymous Option is outside the current container-state pilot"

  -- OptU16: Option UInt16 state. Same legal-width payload needle set as
  -- OptU32, but UInt16 ≠ UInt32 so it is its own pin. Aleo/TON stay on
  -- Option-payload, not OptU128's width needles. Quint/Soroban/OpenVM/
  -- ICP fail on the width needle first, not OptBool's Option-pilot.
  -- Not opening Option-of-UInt16. OptU32 / OptU256 / OptU128 / OptInt
  -- stay.
  let optU16Source :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program OptU16 where\n" ++
    "  state o : Option UInt16\n\n" ++
    "  init() do\n" ++
    "    o := Option.none()\n\n" ++
    "  entry setSome(v : UInt64) : UInt64 do\n" ++
    "    o := Option.some(0)\n" ++
    "    return v\n\n" ++
    "end ProofForgeV2.Examples\n"
  let optU16V1 ← match ← session.selectProgramV1 optU16Source
      "<targets-opt-u16>" "Examples.OptU16" none with
    | .ok v => pure v
    | .error e => throw <| IO.userError s!"OptU16 select: {e.render}"
  let optU16Compiled ← liftResult <| Compiler.compileValidatedSourceV1 optU16V1
  expectMaterializePlanInvariantV1 "OptU16" TargetId.evm TargetKind.evm
    optU16Compiled "Option state admits only UInt64 payload"
  expectMaterializePlanInvariantV1 "OptU16" TargetId.solana TargetKind.solana
    optU16Compiled "Option state 'o' element must be UInt64"
  for (target, kind) in #[
      (TargetId.near, TargetKind.near),
      (TargetId.noir, TargetKind.noir),
      (TargetId.aleo, TargetKind.aleo),
      (TargetId.psy, TargetKind.psy),
      (TargetId.cosmwasm, TargetKind.cosmwasm),
      (TargetId.ton, TargetKind.ton)] do
    expectMaterializePlanInvariantV1 "OptU16" target kind optU16Compiled
      "Option state 'o' requires UInt64 payload"
  for (target, kind) in #[
      (TargetId.quint, TargetKind.quint),
      (TargetId.soroban, TargetKind.soroban),
      (TargetId.openvm, TargetKind.openvm),
      (TargetId.icp, TargetKind.icp)] do
    expectMaterializePlanInvariantV1 "OptU16" target kind optU16Compiled
      "only anonymous UInt64/Int64 widths are supported"

  -- OptU8: Option UInt8 state. Same legal-width payload needle set as
  -- OptU16, but UInt8 ≠ UInt16 so it is its own pin (last narrow
  -- unsigned Option width). Aleo/TON stay on Option-payload, not
  -- OptU128's width needles. Not opening Option-of-UInt8. OptU16 /
  -- OptU32 / OptU256 / OptU128 stay.
  let optU8Source :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program OptU8 where\n" ++
    "  state o : Option UInt8\n\n" ++
    "  init() do\n" ++
    "    o := Option.none()\n\n" ++
    "  entry setSome(v : UInt64) : UInt64 do\n" ++
    "    o := Option.some(0)\n" ++
    "    return v\n\n" ++
    "end ProofForgeV2.Examples\n"
  let optU8V1 ← match ← session.selectProgramV1 optU8Source
      "<targets-opt-u8>" "Examples.OptU8" none with
    | .ok v => pure v
    | .error e => throw <| IO.userError s!"OptU8 select: {e.render}"
  let optU8Compiled ← liftResult <| Compiler.compileValidatedSourceV1 optU8V1
  expectMaterializePlanInvariantV1 "OptU8" TargetId.evm TargetKind.evm
    optU8Compiled "Option state admits only UInt64 payload"
  expectMaterializePlanInvariantV1 "OptU8" TargetId.solana TargetKind.solana
    optU8Compiled "Option state 'o' element must be UInt64"
  for (target, kind) in #[
      (TargetId.near, TargetKind.near),
      (TargetId.noir, TargetKind.noir),
      (TargetId.aleo, TargetKind.aleo),
      (TargetId.psy, TargetKind.psy),
      (TargetId.cosmwasm, TargetKind.cosmwasm),
      (TargetId.ton, TargetKind.ton)] do
    expectMaterializePlanInvariantV1 "OptU8" target kind optU8Compiled
      "Option state 'o' requires UInt64 payload"
  for (target, kind) in #[
      (TargetId.quint, TargetKind.quint),
      (TargetId.soroban, TargetKind.soroban),
      (TargetId.openvm, TargetKind.openvm),
      (TargetId.icp, TargetKind.icp)] do
    expectMaterializePlanInvariantV1 "OptU8" target kind optU8Compiled
      "only anonymous UInt64/Int64 widths are supported"

  -- OptI32: Option Int32 state. All twelve stay named FC. Aleo/CW/TON
  -- fail on width / narrow-Int first, not OptInt/OptU32's
  -- Option-payload. Int32 ≠ Int64 and ≠ UInt32. Not opening
  -- Option-of-Int32. OptU8 / OptInt / OptU32 / ArrI32 stay.
  let optI32Source :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program OptI32 where\n" ++
    "  state o : Option Int32\n\n" ++
    "  init() do\n" ++
    "    o := Option.none()\n\n" ++
    "  entry setSome(v : UInt64) : UInt64 do\n" ++
    "    o := Option.some(0)\n" ++
    "    return v\n\n" ++
    "end ProofForgeV2.Examples\n"
  let optI32V1 ← match ← session.selectProgramV1 optI32Source
      "<targets-opt-i32>" "Examples.OptI32" none with
    | .ok v => pure v
    | .error e => throw <| IO.userError s!"OptI32 select: {e.render}"
  let optI32Compiled ← liftResult <| Compiler.compileValidatedSourceV1 optI32V1
  expectMaterializePlanInvariantV1 "OptI32" TargetId.evm TargetKind.evm
    optI32Compiled "Option state admits only UInt64 payload"
  expectMaterializePlanInvariantV1 "OptI32" TargetId.solana TargetKind.solana
    optI32Compiled "Option state 'o' element must be UInt64"
  for (target, kind) in #[
      (TargetId.near, TargetKind.near),
      (TargetId.noir, TargetKind.noir),
      (TargetId.psy, TargetKind.psy),
      (TargetId.aleo, TargetKind.aleo)] do
    expectMaterializePlanInvariantV1 "OptI32" target kind optI32Compiled
      "Option state 'o' requires UInt64 payload"
  expectMaterializePlanInvariantV1 "OptI32" TargetId.cosmwasm TargetKind.cosmwasm
    optI32Compiled "Option state 'o' requires UInt64 payload"
  expectMaterializePlanInvariantV1 "OptI32" TargetId.ton TargetKind.ton
    optI32Compiled "Option state 'o' requires UInt64 payload"
  for (target, kind) in #[
      (TargetId.quint, TargetKind.quint),
      (TargetId.soroban, TargetKind.soroban),
      (TargetId.openvm, TargetKind.openvm),
      (TargetId.icp, TargetKind.icp)] do
    expectMaterializePlanInvariantV1 "OptI32" target kind optI32Compiled
      "only anonymous UInt64/Int64 widths are supported"

  -- OptI16: Option Int16 state. Same twelve named-FC needles as
  -- OptI32, but Int16 ≠ Int32 so it is its own pin. Aleo/CW/TON stay
  -- on width / narrow-Int, not OptInt/OptU16's Option-payload. Not
  -- opening Option-of-Int16. OptI32 / OptU16 / OptInt / MapI32 stay.
  let optI16Source :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program OptI16 where\n" ++
    "  state o : Option Int16\n\n" ++
    "  init() do\n" ++
    "    o := Option.none()\n\n" ++
    "  entry setSome(v : UInt64) : UInt64 do\n" ++
    "    o := Option.some(0)\n" ++
    "    return v\n\n" ++
    "end ProofForgeV2.Examples\n"
  let optI16V1 ← match ← session.selectProgramV1 optI16Source
      "<targets-opt-i16>" "Examples.OptI16" none with
    | .ok v => pure v
    | .error e => throw <| IO.userError s!"OptI16 select: {e.render}"
  let optI16Compiled ← liftResult <| Compiler.compileValidatedSourceV1 optI16V1
  expectMaterializePlanInvariantV1 "OptI16" TargetId.evm TargetKind.evm
    optI16Compiled "Option state admits only UInt64 payload"
  expectMaterializePlanInvariantV1 "OptI16" TargetId.solana TargetKind.solana
    optI16Compiled "Option state 'o' element must be UInt64"
  for (target, kind) in #[
      (TargetId.near, TargetKind.near),
      (TargetId.noir, TargetKind.noir),
      (TargetId.psy, TargetKind.psy),
      (TargetId.aleo, TargetKind.aleo)] do
    expectMaterializePlanInvariantV1 "OptI16" target kind optI16Compiled
      "Option state 'o' requires UInt64 payload"
  expectMaterializePlanInvariantV1 "OptI16" TargetId.cosmwasm TargetKind.cosmwasm
    optI16Compiled "Option state 'o' requires UInt64 payload"
  expectMaterializePlanInvariantV1 "OptI16" TargetId.ton TargetKind.ton
    optI16Compiled "Option state 'o' requires UInt64 payload"
  for (target, kind) in #[
      (TargetId.quint, TargetKind.quint),
      (TargetId.soroban, TargetKind.soroban),
      (TargetId.openvm, TargetKind.openvm),
      (TargetId.icp, TargetKind.icp)] do
    expectMaterializePlanInvariantV1 "OptI16" target kind optI16Compiled
      "only anonymous UInt64/Int64 widths are supported"

  -- OptI8: Option Int8 state. Same twelve named-FC needles as OptI16,
  -- but Int8 ≠ Int16 so it is its own pin (last narrow signed Option
  -- width). Aleo/CW/TON stay on width / narrow-Int, not OptInt/OptU8's
  -- Option-payload. Not opening Option-of-Int8. OptI16 / OptI32 /
  -- OptU8 / MapI32Key stay.
  let optI8Source :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program OptI8 where\n" ++
    "  state o : Option Int8\n\n" ++
    "  init() do\n" ++
    "    o := Option.none()\n\n" ++
    "  entry setSome(v : UInt64) : UInt64 do\n" ++
    "    o := Option.some(0)\n" ++
    "    return v\n\n" ++
    "end ProofForgeV2.Examples\n"
  let optI8V1 ← match ← session.selectProgramV1 optI8Source
      "<targets-opt-i8>" "Examples.OptI8" none with
    | .ok v => pure v
    | .error e => throw <| IO.userError s!"OptI8 select: {e.render}"
  let optI8Compiled ← liftResult <| Compiler.compileValidatedSourceV1 optI8V1
  expectMaterializePlanInvariantV1 "OptI8" TargetId.evm TargetKind.evm
    optI8Compiled "Option state admits only UInt64 payload"
  expectMaterializePlanInvariantV1 "OptI8" TargetId.solana TargetKind.solana
    optI8Compiled "Option state 'o' element must be UInt64"
  for (target, kind) in #[
      (TargetId.near, TargetKind.near),
      (TargetId.noir, TargetKind.noir),
      (TargetId.psy, TargetKind.psy),
      (TargetId.aleo, TargetKind.aleo)] do
    expectMaterializePlanInvariantV1 "OptI8" target kind optI8Compiled
      "Option state 'o' requires UInt64 payload"
  expectMaterializePlanInvariantV1 "OptI8" TargetId.cosmwasm TargetKind.cosmwasm
    optI8Compiled "Option state 'o' requires UInt64 payload"
  expectMaterializePlanInvariantV1 "OptI8" TargetId.ton TargetKind.ton
    optI8Compiled "Option state 'o' requires UInt64 payload"
  for (target, kind) in #[
      (TargetId.quint, TargetKind.quint),
      (TargetId.soroban, TargetKind.soroban),
      (TargetId.openvm, TargetKind.openvm),
      (TargetId.icp, TargetKind.icp)] do
    expectMaterializePlanInvariantV1 "OptI8" target kind optI8Compiled
      "only anonymous UInt64/Int64 widths are supported"

  -- N5: Commit identity admitted on EVM/Solana/NEAR (Plan passthrough into
  -- commitment state). Noir declines (public relation slots cannot hold
  -- commitment labels). Psy declines. ContextRead declined on every Phase-1
  -- target (PlanSchema / host clock ABI frozen this slice).
  let commitSource :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program CommitSeal where\n" ++
    "  state commitment sealed : UInt64\n\n" ++
    "  init() do\n" ++
    "    sealed := 0\n\n" ++
    "  entry run(x : UInt64) : UInt64 do\n" ++
    "    sealed := commit(x)\n" ++
    "    return x\n\n" ++
    "end ProofForgeV2.Examples\n"
  let commitV1 ← match ← session.selectProgramV1 commitSource
      "<targets-n5-commit>" "Examples.CommitSeal" none with
    | .ok v => pure v
    | .error e => throw <| IO.userError s!"N5 commit select: {e.render}"
  let commitCompiled ← liftResult <| Compiler.compileValidatedSourceV1 commitV1
  -- Extra eight filled from probe; identity Commit only; not B-COMMIT-ZK.
  for target in [TargetId.evm, TargetId.solana, TargetId.near,
      TargetId.cosmwasm, TargetId.ton, TargetId.aleo] do
    match materializeSelected target commitCompiled with
    | .ok _ => pure ()
    | .error e =>
        throw <| IO.userError s!"N5 commit: {target} must admit Commit identity, got {e.render}"
  for target in [TargetId.noir, TargetId.psy, TargetId.quint, TargetId.soroban,
      TargetId.icp, TargetId.openvm] do
    match materializeSelected target commitCompiled with
    | .ok _ => throw <| IO.userError s!"N5 commit: {target} must decline Commit"
    | .error e =>
        expect ((e.render).contains "Commit" || (e.render).contains "commit" ||
            (e.render).contains "commitment" ||
            (e.render).contains "unsupported" || (e.render).contains "pilot" ||
            (e.render).contains "public")
          s!"N5 commit {target} message must cite Commit/commitment boundary, got {e.render}"

  let ctxSource :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program CtxTime where\n" ++
    "  state public pad : UInt64\n\n" ++
    "  init() do\n" ++
    "    pad := 0\n\n" ++
    "  entry now() : UInt64 do\n" ++
    "    return context.unixTimeSeconds\n\n" ++
    "end ProofForgeV2.Examples\n"
  let ctxV1 ← match ← session.selectProgramV1 ctxSource
      "<targets-n5-context>" "Examples.CtxTime" none with
    | .ok v => pure v
    | .error e => throw <| IO.userError s!"N5 context select: {e.render}"
  let ctxCompiled ← liftResult <| Compiler.compileValidatedSourceV1 ctxV1
  -- B-CTX-OPEN (2026-08-04): EVM (timestamp()), NEAR (block_timestamp/1e9),
  -- CosmWasm (Env "time" ns /1e9, BL-37) and TON (blockchain.now(), BL-38)
  -- admit unixTimeSeconds. CAP-1a (2026-08-15): ICP admits ic0.time ns÷10⁹.
  -- Circuit-class + Quint/Soroban/OpenVM stay FC; Solana unixTime stays FC
  -- (CAP-D-SOL-TIME not picked). Unanchored public-input injection would
  -- only prove "the program used T", never "T is the real chain time".
  let _ ← liftResult <| materializeSelected TargetId.evm ctxCompiled
  let _ ← liftResult <| materializeSelected TargetId.near ctxCompiled
  let _ ← liftResult <| materializeSelected TargetId.cosmwasm ctxCompiled
  let _ ← liftResult <| materializeSelected TargetId.ton ctxCompiled
  let _ ← liftResult <| materializeSelected TargetId.icp ctxCompiled
  for target in [TargetId.solana, TargetId.noir, TargetId.psy, TargetId.aleo,
      TargetId.openvm, TargetId.quint, TargetId.soroban] do
    match materializeSelected target ctxCompiled with
    | .ok _ =>
        throw <| IO.userError s!"N5 context: {target} must decline ContextRead"
    | .error e =>
        expect ((e.render).contains "ContextRead" ||
            (e.render).contains "context" ||
            (e.render).contains "unix-time" ||
            (e.render).contains "unsupported" ||
            (e.render).contains "pilot")
          s!"N5 context {target} message must cite ContextRead boundary, got {e.render}"

  -- ADR-0031 S4: context.attachedValue. EVM admits CALLVALUE; NEAR admits
  -- attached_deposit (entry/init; view FC); CosmWasm admits MessageInfo.funds
  -- (execute/init; query FC). Other implemented targets stay Plan-fail-closed.
  let attachedSource :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program CtxAttached where\n" ++
    "  state public pad : UInt64\n\n" ++
    "  init() do\n" ++
    "    pad := 0\n\n" ++
    "  entry collect() : UInt64 do\n" ++
    "    return context.attachedValue\n\n" ++
    "end ProofForgeV2.Examples\n"
  let attachedV1 ← match ← session.selectProgramV1 attachedSource
      "<targets-s4-attached>" "Examples.CtxAttached" none with
    | .ok v => pure v
    | .error e => throw <| IO.userError s!"S4 attached select: {e.render}"
  let attachedCompiled ← liftResult <| Compiler.compileValidatedSourceV1 attachedV1
  let _ ← liftResult <| materializeSelected TargetId.evm attachedCompiled
  let _ ← liftResult <| materializeSelected TargetId.near attachedCompiled
  let _ ← liftResult <| materializeSelected TargetId.cosmwasm attachedCompiled
  -- Quint/Soroban stay FC (no host); do not open attachedValue.
  for target in [TargetId.ton,
      TargetId.solana, TargetId.noir, TargetId.psy, TargetId.aleo,
      TargetId.icp, TargetId.openvm, TargetId.quint, TargetId.soroban] do
    match materializeSelected target attachedCompiled with
    | .ok _ =>
        throw <| IO.userError s!"S4 attached: {target} must decline ContextRead attachedValue"
    | .error e =>
        expect ((e.render).contains "ContextRead" ||
            (e.render).contains "context" ||
            (e.render).contains "attached" ||
            (e.render).contains "unsupported" ||
            (e.render).contains "pilot")
          s!"S4 attached {target} message must cite ContextRead/attached boundary, got {e.render}"

  -- ADR-0031 S1 / ADR-0030 E3: context.caller Principal ContextRead.
  -- EVM admits ADR-0025 encoding (CALLER → u32le(20)||addr20 leaves;
  -- Bool compare fixture). NEAR admits predecessor_account_id →
  -- u32le(L)||account-id-utf8 leaves (view stays FC; entry/init only).
  -- Solana's sole CPI product profile binds the signer-role `pf_caller` pubkey;
  -- Noir/Psy stay Plan-fail-closed until their own chain-anchor cutover.
  let callerSource :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program CtxCaller where\n" ++
    "  state public pad : UInt64\n\n" ++
    "  init() do\n" ++
    "    pad := 0\n\n" ++
    "  entry who(a : Principal) : Bool do\n" ++
    "    return context.caller == a\n\n" ++
    "end ProofForgeV2.Examples\n"
  let callerV1 ← match ← session.selectProgramV1 callerSource
      "<targets-b-ctx-caller>" "Examples.CtxCaller" none with
    | .ok v => pure v
    | .error e => throw <| IO.userError s!"B-ctx caller select: {e.render}"
  let callerCompiled ← liftResult <| Compiler.compileValidatedSourceV1 callerV1
  let _ ← liftResult <| materializeSelected TargetId.evm callerCompiled
  let _ ← liftResult <| materializeSelected TargetId.near callerCompiled
  let _ ← liftResult <| materializeSelected TargetId.solana callerCompiled
  -- CosmWasm entry admits caller; Quint/Soroban/Aleo/TON stay FC
  -- (type-closure or named). Not ICP caller encoding.
  let _ ← liftResult <| materializeSelected TargetId.cosmwasm callerCompiled
  for target in [TargetId.noir, TargetId.psy, TargetId.icp, TargetId.openvm,
      TargetId.ton, TargetId.aleo, TargetId.quint, TargetId.soroban] do
    match materializeSelected target callerCompiled with
    | .ok _ =>
        throw <| IO.userError s!"B-ctx caller: {target} must decline ContextRead caller"
    | .error e =>
        expect ((e.render).contains "ContextRead" ||
            (e.render).contains "context" ||
            (e.render).contains "caller" ||
            (e.render).contains "unsupported" ||
            (e.render).contains "pilot" ||
            (e.render).contains "Principal")
          s!"B-ctx caller {target} message must cite ContextRead/caller boundary, got {e.render}"

  -- ADR-0031 S2/S3: exact cross-target dispatch for blockHeight, chainId,
  -- and self. These pins follow each target-owned LowerSemanticV1 dispatcher;
  -- every decline must remain a target-specific PF-PLAN-INVARIANT.
  -- Fresh parser session: shared elab env can lose `context` root resolution
  -- after earlier Principal/ContextRead fixtures in this long suite.
  let session ← Language.Loader.ParserSession.create
  let blockHeightSource :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program CtxBlockHeightMatrix where\n" ++
    "  state public pad : UInt64\n\n" ++
    "  init() do\n" ++
    "    pad := 0\n\n" ++
    "  entry read() : UInt64 do\n" ++
    "    return context.blockHeight\n\n" ++
    "end ProofForgeV2.Examples\n"
  let blockHeightV1 ← match ← session.selectProgramV1 blockHeightSource
      "<targets-context-block-height-matrix>" "Examples.CtxBlockHeightMatrix" none with
    | .ok v => pure v
    | .error e => throw <| IO.userError s!"context.blockHeight matrix select: {e.render}"
  let blockHeightCompiled ← liftResult <|
    Compiler.compileValidatedSourceV1 blockHeightV1
  for target in [TargetId.evm, TargetId.near, TargetId.cosmwasm, TargetId.solana] do
    expectContextMatrixAdmit "context.blockHeight" target blockHeightCompiled
  expectContextMatrixFailClosed "context.blockHeight/ton"
    TargetId.ton .ton
    "unsupported Ton semantic shape: ContextRead (context.blockHeight) is not admitted (no honest TON block-height binding in pilot)"
    blockHeightCompiled
  expectContextMatrixFailClosed "context.blockHeight/noir"
    TargetId.noir .noir
    s!"unsupported Noir semantic shape: ContextRead '{blockHeightContextKeyV1.value}' has no Noir host binding (blockHeight stays fail closed)"
    blockHeightCompiled
  expectContextMatrixFailClosed "context.blockHeight/aleo"
    TargetId.aleo .aleo
    s!"unsupported Aleo semantic shape: ContextRead '{blockHeightContextKeyV1.value}' has no Aleo host binding (blockHeight stays fail closed)"
    blockHeightCompiled
  expectContextMatrixFailClosed "context.blockHeight/psy"
    TargetId.psy .psy
    "unsupported Psy semantic shape: context.blockHeight has no DPN height binding (FC). Use call pf.context.checkpointId() for checkpoint identity"
    blockHeightCompiled
  expectContextMatrixFailClosed "context.blockHeight/quint"
    TargetId.quint .quint
    s!"unsupported Quint semantic shape: ContextRead '{blockHeightContextKeyV1.value}' has no Quint host binding (unixTimeSeconds/blockHeight/attachedValue/chainId stay fail closed)"
    blockHeightCompiled
  expectContextMatrixFailClosed "context.blockHeight/soroban"
    TargetId.soroban .soroban
    s!"unsupported Soroban semantic shape: ContextRead '{blockHeightContextKeyV1.value}' has no Soroban host binding (unixTimeSeconds/blockHeight/attachedValue/chainId stay fail closed)"
    blockHeightCompiled
  expectContextMatrixFailClosed "context.blockHeight/icp"
    TargetId.icp .icp
    s!"unsupported ICP semantic shape: ContextRead '{blockHeightContextKeyV1.value}' has no Icp host binding (blockHeight/attachedValue/chainId stay fail closed)"
    blockHeightCompiled
  expectContextMatrixFailClosed "context.blockHeight/openvm"
    TargetId.openvm .openvm
    s!"unsupported OpenVM semantic shape: ContextRead '{blockHeightContextKeyV1.value}' has no OpenVM host binding (unixTimeSeconds/blockHeight/attachedValue/chainId stay fail closed)"
    blockHeightCompiled

  let session ← Language.Loader.ParserSession.create
  let chainIdSource :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program CtxChainIdMatrix where\n" ++
    "  state public pad : UInt64\n\n" ++
    "  init() do\n" ++
    "    pad := 0\n\n" ++
    "  entry read() : UInt64 do\n" ++
    "    return context.chainId\n\n" ++
    "end ProofForgeV2.Examples\n"
  let chainIdV1 ← match ← session.selectProgramV1 chainIdSource
      "<targets-context-chain-id-matrix>" "Examples.CtxChainIdMatrix" none with
    | .ok v => pure v
    | .error e => throw <| IO.userError s!"context.chainId matrix select: {e.render}"
  let chainIdCompiled ← liftResult <| Compiler.compileValidatedSourceV1 chainIdV1
  expectContextMatrixAdmit "context.chainId" TargetId.evm chainIdCompiled
  expectContextMatrixFailClosed "context.chainId/near"
    TargetId.near .near
    "unsupported NEAR semantic shape: ContextRead context.chainId has no exact host counterpart (fail closed)"
    chainIdCompiled
  expectContextMatrixFailClosed "context.chainId/cosmwasm"
    TargetId.cosmwasm .cosmwasm
    "unsupported CosmWasm semantic shape: ContextRead context.chainId has no exact UInt64 host counterpart (string chain_id fail closed)"
    chainIdCompiled
  expectContextMatrixFailClosed "context.chainId/solana"
    TargetId.solana .solana
    s!"CPI derive: unknown ContextRead key '{chainIdContextKeyV1.value}'"
    chainIdCompiled
  expectContextMatrixFailClosed "context.chainId/ton"
    TargetId.ton .ton
    s!"unsupported Ton semantic shape: ContextRead '{chainIdContextKeyV1.value}' has no Ton host binding (chainId stays fail closed)"
    chainIdCompiled
  expectContextMatrixFailClosed "context.chainId/noir"
    TargetId.noir .noir
    s!"unsupported Noir semantic shape: ContextRead '{chainIdContextKeyV1.value}' has no Noir host binding (chainId stays fail closed)"
    chainIdCompiled
  expectContextMatrixFailClosed "context.chainId/aleo"
    TargetId.aleo .aleo
    s!"unsupported Aleo semantic shape: ContextRead '{chainIdContextKeyV1.value}' has no Aleo host binding (chainId stays fail closed)"
    chainIdCompiled
  expectContextMatrixFailClosed "context.chainId/psy"
    TargetId.psy .psy
    s!"unsupported Psy semantic shape: ContextRead '{chainIdContextKeyV1.value}' has no Psy host binding (chainId stays fail closed)"
    chainIdCompiled
  expectContextMatrixFailClosed "context.chainId/quint"
    TargetId.quint .quint
    s!"unsupported Quint semantic shape: ContextRead '{chainIdContextKeyV1.value}' has no Quint host binding (unixTimeSeconds/blockHeight/attachedValue/chainId stay fail closed)"
    chainIdCompiled
  expectContextMatrixFailClosed "context.chainId/soroban"
    TargetId.soroban .soroban
    s!"unsupported Soroban semantic shape: ContextRead '{chainIdContextKeyV1.value}' has no Soroban host binding (unixTimeSeconds/blockHeight/attachedValue/chainId stay fail closed)"
    chainIdCompiled
  expectContextMatrixFailClosed "context.chainId/icp"
    TargetId.icp .icp
    s!"unsupported ICP semantic shape: ContextRead '{chainIdContextKeyV1.value}' has no Icp host binding (blockHeight/attachedValue/chainId stay fail closed)"
    chainIdCompiled
  expectContextMatrixFailClosed "context.chainId/openvm"
    TargetId.openvm .openvm
    s!"unsupported OpenVM semantic shape: ContextRead '{chainIdContextKeyV1.value}' has no OpenVM host binding (unixTimeSeconds/blockHeight/attachedValue/chainId stay fail closed)"
    chainIdCompiled

  let session ← Language.Loader.ParserSession.create
  let selfSource :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program CtxSelfMatrix where\n" ++
    "  state public pad : UInt64\n\n" ++
    "  init() do\n" ++
    "    pad := 0\n\n" ++
    "  entry same() : Bool do\n" ++
    "    return context.contractId == context.contractId\n\n" ++
    "end ProofForgeV2.Examples\n"
  let selfV1 ← match ← session.selectProgramV1 selfSource
      "<targets-context-self-matrix>" "Examples.CtxSelfMatrix" none with
    | .ok v => pure v
    | .error e => throw <| IO.userError s!"context.contractId matrix select: {e.render}"
  let selfCompiled ← liftResult <| Compiler.compileValidatedSourceV1 selfV1
  for target in [TargetId.evm, TargetId.near, TargetId.cosmwasm] do
    expectContextMatrixAdmit "context.contractId" target selfCompiled
  expectContextMatrixFailClosed "context.contractId/solana"
    TargetId.solana .solana
    s!"CPI derive: unknown ContextRead key '{selfContextKeyV1.value}'"
    selfCompiled
  expectContextMatrixFailClosed "context.contractId/ton"
    TargetId.ton .ton
    "unsupported Ton semantic shape: only UInt{8,16,32,64,128,256}, Int{8,16,32,64}, Unit, Bool, named Struct/Enum, and anonymous Array/Map/Bytes/Option are supported (no Field/Principal; Int128/256 fail closed)"
    selfCompiled
  expectContextMatrixFailClosed "context.contractId/noir"
    TargetId.noir .noir
    "unsupported Noir semantic shape: ContextRead (context.self) is not admitted by pilot context policy (Principal to Noir address mapping deferred)"
    selfCompiled
  expectContextMatrixFailClosed "context.contractId/aleo"
    TargetId.aleo .aleo
    "unsupported Aleo semantic shape: only UInt64, UInt32, UInt16, UInt8, UInt128, Int64, Int32, Int16, Int8, Unit, Bool, Field(bls12-377-fr), named Struct/Enum, Array UInt64, Map UInt64 UInt64, Bytes N, and Option UInt64 (state/return; not params) are supported (Aleo native field is BLS12-377 Fr / Edwards BLS scalar, exact modulus match; bn254 Fr and Goldilocks fail closed as wrong modulus; Option of non-UInt64/nested/params + Principal/String stay fail-closed; UInt256 and Int128/256 stay fail-closed)"
    selfCompiled
  expectContextMatrixFailClosed "context.contractId/psy"
    TargetId.psy .psy
    "unsupported Psy semantic shape: context.self (Principal) is not a Psy address. Use call pf.context.contractId() for DPN ExecutionContext ids"
    selfCompiled
  expectContextMatrixFailClosed "context.contractId/quint"
    TargetId.quint .quint
    "unsupported Quint semantic shape: op is outside Q0"
    selfCompiled
  expectContextMatrixFailClosed "context.contractId/soroban"
    TargetId.soroban .soroban
    "unsupported Soroban semantic shape: only anonymous UInt64, Int64, Bool, Unit, Array UInt64 N state flatten, Option UInt64 2-leaf state, and Map UInt64 UInt64 cap-8 flatten are supported (narrow Int/Field/Principal/aggregates/Bytes fail closed)"
    selfCompiled
  expectContextMatrixFailClosed "context.contractId/icp"
    TargetId.icp .icp
    "unsupported ICP semantic shape: only anonymous UInt64, Int64, Bool, Unit, and Array UInt64 N state flatten are supported (narrow Int/Field/Principal/aggregates/Map/Option/Bytes/String fail closed on the ICP-2 Counter/StateCell envelope)"
    selfCompiled
  expectContextMatrixFailClosed "context.contractId/openvm"
    TargetId.openvm .openvm
    "unsupported OpenVM semantic shape: only anonymous UInt64, Int64, Bool, Unit, Array UInt64 N state flatten, Option UInt64 2-leaf flatten, and Map UInt64 UInt64 cap-8 flatten are supported (narrow Int/Field/Principal/aggregates/Bytes/nested Option fail closed)"
    selfCompiled

  -- B-RET-ABI: named Struct view return. EVM + Noir + Solana + NEAR + Psy +
  -- CosmWasm + TON admit (multi-leaf ABI: EVM tuple / Noir leaves /
  -- N×8 LE / [Felt; N] / JSON decimals / get-method stack); Aleo admits
  -- view-over-state as a query descriptor (`kind=computed`, leaf array).
  -- PairRetEntry keeps the non-state entry multi-output Instructions pin.
  let pairRetSource :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program PairRet where\n" ++
    "  struct Pair where\n" ++
    "    a : UInt64\n" ++
    "    b : UInt64\n\n" ++
    "  state p : Pair\n\n" ++
    "  init(x : UInt64, y : UInt64) do\n" ++
    "    p := Pair.new(x, y)\n\n" ++
    "  view getPair() : Pair do\n" ++
    "    return p\n\n" ++
    "end ProofForgeV2.Examples\n"
  let pairV1 ← match ← session.selectProgramV1 pairRetSource
      "<targets-b-ret-abi>" "Examples.PairRet" none with
    | .ok v => pure v
    | .error e => throw <| IO.userError s!"B-RET-ABI select: {e.render}"
  let pairCompiled ← liftResult <| Compiler.compileValidatedSourceV1 pairV1
  -- EVM admits: plan has .returnAggregate.
  let _evmPair ← liftResult <| planEvm pairCompiled
  -- Noir admits: plan has .returnAggregate.
  let _noirPair ← liftResult <| planNoir pairCompiled
  -- Solana admits: plan has .aggregate resultKind (B-RET-ABI).
  let _solanaPair ← liftResult <| planSolana pairCompiled
  -- NEAR admits: plan has .aggregate resultKind (B-RET-ABI).
  let _nearPair ← liftResult <| planNear pairCompiled
  -- Aleo: view-over-state aggregate return is a query descriptor only.
  let aleoPairOut ← liftResult <| materializeSelected TargetId.aleo pairCompiled
  expect (!(MaterializedArtifactsV1.filesOf aleoPairOut).isEmpty)
    "B-RET-ABI: aleo must materialize view aggregate return as query descriptor"
  -- Aleo admits non-state entry aggregate returns as native multi-output Instructions.
  let aleoPairEntrySource :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program PairRetEntry where\n" ++
    "  struct Pair where\n" ++
    "    a : UInt64\n" ++
    "    b : UInt64\n\n" ++
    "  entry makePair(x : UInt64, y : UInt64) : Pair do\n" ++
    "    return Pair.new(x, y)\n\n" ++
    "end ProofForgeV2.Examples\n"
  let pairEntryV1 ← match ← session.selectProgramV1 aleoPairEntrySource
      "<targets-b-ret-abi-aleo>" "Examples.PairRetEntry" none with
    | .ok v => pure v
    | .error e => throw <| IO.userError s!"B-RET-ABI aleo-entry select: {e.render}"
  let pairEntryCompiled ← liftResult <| Compiler.compileValidatedSourceV1 pairEntryV1
  let _aleoPair ← liftResult <| planAleo pairEntryCompiled
  -- Psy admits: view aggregate return lowers to [Felt; N] (B-RET-ABI).
  let _psyPair ← liftResult <| planPsy pairCompiled
  -- CosmWasm admits view aggregate return (JSON array of decimals).
  match materializeSelected TargetId.cosmwasm pairCompiled with
  | .ok _ => pure ()
  | .error e =>
      throw <| IO.userError
        s!"B-RET-ABI: cosmwasm must admit view aggregate return, got {e.render}"
  -- TON admits view aggregate return (multi-stack get method).
  match materializeSelected TargetId.ton pairCompiled with
  | .ok _ => pure ()
  | .error e =>
      throw <| IO.userError
        s!"B-RET-ABI: ton must admit view aggregate return, got {e.render}"
  -- Extra from probe: plan-admit targets also materialize (files nonempty).
  -- Quint/Soroban/ICP/OpenVM stay envelope FC. Aleo query-descriptor pin
  -- is above. Envelope-4 stay FC.
  for target in [TargetId.evm, TargetId.solana, TargetId.near, TargetId.noir,
      TargetId.psy] do
    let out ← liftResult <| materializeSelected target pairCompiled
    expect (!(MaterializedArtifactsV1.filesOf out).isEmpty)
      s!"B-RET-ABI: {target} must materialize view aggregate return"
  for target in [TargetId.quint, TargetId.soroban, TargetId.icp, TargetId.openvm] do
    match materializeSelected target pairCompiled with
    | .ok _ =>
        throw <| IO.userError s!"B-RET-ABI: {target} must decline view aggregate return"
    | .error e =>
        expect ((e.render).contains "aggregate" ||
            (e.render).contains "return" ||
            (e.render).contains "named" ||
            (e.render).contains "unsupported" ||
            (e.render).contains "pilot" ||
            (e.render).contains "public" ||
            (e.render).contains "query")
          s!"B-RET-ABI {target} message must cite aggregate/return boundary, got {e.render}"

unsafe def run : IO Unit := do
  runSemanticPlanLeafFast
  runProductLighthouse
  runWideIntegerNeedles
  runNamedAndArrayNeedles
  runSignedContainerNeedles
  runRemainingNeedles

end Tests.Materialization
