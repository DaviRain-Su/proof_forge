import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Core.Crypto
import ProofForgeV2.Examples.Counter
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

/-- Capability-gated plan for the single retained-semantic compiled carrier. -/
private def planEvm (compiled : CompiledSemanticV1) : CompileResult Targets.Evm.Plan := do
  let selection ← resolveBuildSelectionV1 TargetId.evm none
  let capability ← Targets.resolveEngineeringRequirementsV1 selection compiled
  Targets.Evm.planFromCapability capability

/-- Legacy-only helper: unwraps Solana `planFromCapability` `.legacy` carrier. -/
private def planSolana (compiled : CompiledSemanticV1) : CompileResult Targets.Solana.Plan := do
  let selection ← resolveBuildSelectionV1 TargetId.solana none
  let capability ← Targets.resolveEngineeringRequirementsV1 selection compiled
  match ← Targets.Solana.planFromCapability capability with
  | .legacy plan => pure plan
  | .cpi _ =>
      throw <| .planInvariant .solana
        "test helper planSolana: expected .legacy Plan, got .cpi"

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

/-- Legacy-only helper: unwraps Solana `irFromCapability` `.legacy` carrier. -/
private def irSolana (compiled : CompiledSemanticV1) : CompileResult Targets.Solana.IR := do
  let selection ← resolveBuildSelectionV1 TargetId.solana none
  let capability ← Targets.resolveEngineeringRequirementsV1 selection compiled
  match ← Targets.Solana.irFromCapability capability with
  | .legacy ir => pure ir
  | .cpi _ =>
      throw <| .planInvariant .solana
        "test helper irSolana: expected .legacy IR, got .cpi"

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
  "  entry answer() : UInt64 do\n" ++
  "    return ANSWER\n"

private def invariantTargetBoundarySourceTextV1 : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n" ++
  "program InvariantTargetBoundary where\n" ++
  "  entry run() : UInt64 do\n" ++
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
    carrier. Until each target owns those contracts, all six product
    materializers must reject them rather than silently omit either table/op. -/
private unsafe def testConstInvariantMaterializationFailClosed : IO Unit := do
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
      (TargetId.near, TargetKind.near, "constants/invariants"),
      (TargetId.noir, TargetKind.noir, "constants/invariants"),
      (TargetId.aleo, TargetKind.aleo, "Constant load"),
      (TargetId.psy, TargetKind.psy, "Constant/CheckedCast")] do
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
      (TargetId.solana, TargetKind.solana, "constants/invariants"),
      (TargetId.near, TargetKind.near, "constants/invariants"),
      (TargetId.noir, TargetKind.noir, "constants/invariants"),
      (TargetId.aleo, TargetKind.aleo, "does not support invariants"),
      (TargetId.psy, TargetKind.psy, "invariants are outside")] do
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
      (TargetId.solana, TargetKind.solana, "only UInt8"),
      (TargetId.near, TargetKind.near, "only UInt8"),
      (TargetId.noir, TargetKind.noir, "only UInt8"),
      (TargetId.psy, TargetKind.psy, "only UInt64")] do
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
  -- Aleo: view-over-state anonymous aggregate return stays fail closed via
  -- the computed-view gate (only bare public-state reads map to leo query).
  match materializeSelected TargetId.aleo compiled with
  | .ok _ =>
      throw <| IO.userError
        "anonymous-result: aleo must decline view-over-state aggregate return"
  | .error e =>
      expect ((e.render).contains "leo query" ||
          (e.render).contains "fail closed" ||
          (e.render).contains "aggregate")
        s!"anonymous-result aleo message must cite the computed-view/aggregate boundary, got {e.render}"
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

private def testSemanticPlanSourceAuthority : IO Unit := do
  for target in #["Evm", "Solana", "Near", "Noir"] do
    let path := s!"ProofForgeV2/Targets/{target}.lean"
    let forbidden ← IO.Process.output {
      cmd := "rg"
      args := #["-n", "alphaResidualOf|makePlanFromAlpha|validateRequirementEnvelope|Semantic\\.deriveRequirements", path]
    }
    expect (forbidden.exitCode == 1)
      s!"{target} Plan body must not retain a residual-alpha route:\n{forbidden.stdout}"
    let required ← IO.Process.output {
      cmd := "rg"
      args := #["-n", "semanticV1Of|validateSemanticProgramV1|makePlanFromSemanticV1", path]
    }
    expect (required.exitCode == 0 &&
        required.stdout.contains "semanticV1Of" &&
        required.stdout.contains "validateSemanticProgramV1" &&
        required.stdout.contains "makePlanFromSemanticV1")
      s!"{target} Plan body must visibly consume retained SemanticProgramV1:\n{required.stdout}"

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
      (·.path == "Ledger.sbpf-plan") |
    throw <| IO.userError "rich add/sub: missing Ledger.sbpf-plan"
  expect (solanaPlanText.contents.contains
      "%4 = checked_sub_u64 %2, %3 else program_error")
    "Solana emitter must retain checked-sub failure routing"
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
  expect (solanaIdl.contents.contains "\"bool\"" &&
      solanaIdl.contents.contains "\"u64-le\"")
    "Solana IDL must carry both bool and u64-le result types"
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
  let some sbpf := solanaOutput.files.find? (·.path == "BranchFlow.sbpf-plan") |
    throw <| IO.userError "branching: missing BranchFlow.sbpf-plan"
  expect (sbpf.contents.contains "case 0 {" && sbpf.contents.contains "default {")
    "branching sbpf-plan must render switch cases and the default region"
  let some wat := nearOutput.files.find? (·.path == "BranchFlow.wat") |
    throw <| IO.userError "branching: missing BranchFlow.wat"
  expect (wat.contents.contains "(if (local.get $t")
    "branching WAT must render region conditions"
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
    target's emitter surface for pure functions (Yul functions, sbpf .fn
    sections, WAT funcs, Noir block-valued selects). -/
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
  let some sbpf := solanaOutput.files.find? (·.path == "FnFlow.sbpf-plan") |
    throw <| IO.userError "fn-call: missing FnFlow.sbpf-plan"
  expect (sbpf.contents.contains ".fn 0 double" &&
      sbpf.contents.contains ".fn 1 check" &&
      sbpf.contents.contains "= call check" &&
      sbpf.contents.contains "= call double")
    "fn-call sbpf-plan must render fn sections and call sites"
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
  let some sbpf := solanaOutput.files.find? (·.path == "EventFlow.sbpf-plan") |
    throw <| IO.userError "emit-revert: missing EventFlow.sbpf-plan"
  expect (sbpf.contents.contains "emit_event Moved" &&
      sbpf.contents.contains "program_error 0x2000")
    "emit-revert sbpf-plan must render the named event and declared error code"
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

/-- ProgramV1 guarded-counter source text for the comparison+assert leaf. -/
private def guardedCounterSourceTextV1 : String :=
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
    the guarded counter: assert(ge) → checkedSub → return, with each target's
    own assert failure rendering. -/
private unsafe def testGuardedCounterSemanticPlans : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source ← liftResult (← session.selectProgramV1
    guardedCounterSourceTextV1 "<targets-guarded>" "Tests.Targets.Guarded" none)
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
      (·.path == "Guarded.sbpf-plan") |
    throw <| IO.userError "guarded: missing Guarded.sbpf-plan"
  expect (solanaPlanText.contents.contains "cmp_ge_u64" &&
      solanaPlanText.contents.contains "else program_error")
    "Solana emitter must retain the ge comparison and assert error routing"
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
  let some sbpf := solanaOutput.files.find? (·.path == "ArithFlow.sbpf-plan") |
    throw <| IO.userError "arith-ops: missing ArithFlow.sbpf-plan"
  expect (sbpf.contents.contains "checked_mul_u64" &&
      sbpf.contents.contains "checked_div_u64" &&
      sbpf.contents.contains "checked_rem_u64" &&
      sbpf.contents.contains "bitnot_u64" &&
      sbpf.contents.contains "bool_not")
    "arith-ops sbpf-plan must render checked mul/div/rem and unary ops"
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
    "EVM addUp must lower let+for into forLoop with counter/maxIterations/init/cond/update/body"
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
  let some sbpf := solanaOutput.files.find? (·.path == "LoopSum.sbpf-plan") |
    throw <| IO.userError "for-loop: missing LoopSum.sbpf-plan"
  expect (sbpf.contents.contains "loop_u64" && sbpf.contents.contains "bound {" &&
      sbpf.contents.contains "program_error 0x1003")
    "for-loop sbpf-plan must render loop_u64 with the loopBoundExceeded policy code"
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
  -- Computed counts reach the shift everywhere (invalidShift is runtime-live).
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
  let some sbpf := solanaOutput.files.find? (·.path == "BitLogic.sbpf-plan") |
    throw <| IO.userError "shift-bit: missing BitLogic.sbpf-plan"
  expect (sbpf.contents.contains "bitand_u64" && sbpf.contents.contains "bitor_u64" &&
      sbpf.contents.contains "bitxor_u64" && sbpf.contents.contains "shl_u64" &&
      sbpf.contents.contains "shr_u64" && sbpf.contents.contains "bool_and" &&
      sbpf.contents.contains "bool_or" && sbpf.contents.contains "0x1004")
    "shift-bit sbpf-plan must render the five op families with the invalidShift code"
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

/-- Noir constant folding must not evaluate 2^k for huge folded counts: a
    count expression like `0xFFFFFFFF - 1` folds to k ≥ 64 and lowers to the
    literal-false invalidShift guard with a dead wrapped literal. Previously
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
    "Noir huge count must render the literal-false invalidShift guard"
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
    keep current sync behavior; EVM/NEAR/Noir keep current async behavior. -/
private unsafe def testCallScheduleSemanticPlans : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source ← liftResult (← session.selectProgramV1
    extFlowSourceTextV1 "<targets-ext-flow>" "Tests.Targets.ExtFlow" none)
  let compiled ← liftResult <| Compiler.compileValidatedSourceV1 source
  -- ExtFlow contains a sync call: NEAR still declines (no sync CPI).
  let nearSel ← liftResult <| resolveBuildSelectionV1 TargetId.near none
  match Targets.resolveEngineeringRequirementsV1 nearSel compiled with
  | .error e =>
      expect (e.code == "PF-REQ-UNSUPPORTED")
        s!"near must reject the sync-call key, got {e.render}"
  | .ok _ =>
      throw <| IO.userError "near unexpectedly supports the sync-call key"
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

-- Fast regression for the retained-V1 target Plan seam and fail-closed tables.
set_option maxRecDepth 10000 in
unsafe def runSemanticPlanLeafFast : IO Unit := do
  testSemanticPlanSourceAuthority
  testConstInvariantMaterializationFailClosed
  testStringInterfaceMaterializationFailClosed
  testIntForMaterializationFailClosed
  testAnonymousResultMaterializationFailClosed
  testRichUInt64SemanticPlans
  testGuardedCounterSemanticPlans
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
unsafe def run : IO Unit := do
  runSemanticPlanLeafFast
  -- Product path: real ValidatedSourceV1 Counter through the capability aggregate.
  -- All six target Plan bodies consume retained SemanticProgramV1; residual-only
  -- alpha fixtures (privateWitness/out-of-S1) cannot enter the shipped Plan surface.
  -- Host-model PrivateSum4 remains isolated test-local characterization, while
  -- capability Accumulator and rich Ledger cover production target consumers.
  let session ← Tests.Language.ParserSession.shared
  let counterV1 ← liftResult (← session.selectProgramV1
    Examples.counterSourceText "<targets-product-counter>"
    Examples.counterModuleNameV1 none)
  let counterCompiled ← liftResult <| Compiler.compileValidatedSourceV1 counterV1
  let counterSourceDigest := CompiledSemanticV1.sourceDigestOf counterCompiled
  let counterSemanticDigest := CompiledSemanticV1.semanticDigestOf counterCompiled
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
  for target in [TargetId.evm, TargetId.solana, TargetId.near, TargetId.noir] do
    let output ← liftResult <| materializeSelected target counterCompiled
    expect (!(MaterializedArtifactsV1.filesOf output).isEmpty)
      s!"{target} must emit at least one artifact"
    expect (MaterializedArtifactsV1.sourceDigestOf output == counterSourceDigest)
      "product carrier must bind the canonical ValidatedSourceV1 digest"
    expect (MaterializedArtifactsV1.semanticDigestOf output == counterSemanticDigest)
      "product carrier must bind the retained SemanticProgramV1 digest"
  -- S6: alpha-direct materialize remains closed; product capability path covers Counter.
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
    "EVM ABI must not retain the Counter template"

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
  | _ => throw <| IO.userError "SolanaPlan must reserve the .sbpf-plan suffix within 240 bytes"
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
    nearPlan.storage.fields[0]! with key := "fixed-counter-key"
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
      #["Accumulator.sbpf-plan", "Accumulator.idl.json"])
    "Solana Accumulator must emit plan then IDL in canonical order"

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
  for target in [TargetId.evm, TargetId.solana, TargetId.near, TargetId.psy, TargetId.aleo,
      TargetId.noir] do
    let out ← liftResult <| materializeSelected target privStateCompiled
    expect (!(MaterializedArtifactsV1.filesOf out).isEmpty)
      s!"N1 priv-state: {target} must materialize"
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
  for target in [TargetId.evm, TargetId.solana, TargetId.near, TargetId.psy, TargetId.aleo] do
    let out ← liftResult <| materializeSelected target commStateCompiled
    expect (!(MaterializedArtifactsV1.filesOf out).isEmpty)
      s!"N1 comm-state: {target} must materialize"
  match materializeSelected TargetId.noir commStateCompiled with
  | .ok _ =>
      throw <| IO.userError "N1 comm-state: Noir must decline commitment state at Plan"
  | .error e =>
      expect ((e.render).contains "commitment state" ||
          (e.render).contains "not representable" ||
          (e.render).contains "commitment binding")
        s!"N1 comm-state Noir message must cite commitment boundary, got {e.render}"

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

  -- N2b: Field bn254_fr product pin — Noir (native Field) + EVM (ADDMOD/MULMOD
  -- + Fermat inv) admit; Solana/NEAR/Psy fail closed at Plan type-closure.
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
  for target in [TargetId.solana, TargetId.near, TargetId.psy] do
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


  -- N2c + B-3 PrincipalAddr + T10/T12 Principal storage pilot.
  -- Normalize admits identity-only Principal (state/params/eq/ne). Wire is
  -- variable-length u32-prefixed 1..4096 body. T10 opens EVM; T12 opens
  -- Solana/NEAR/Noir state/param leaf storage (len + 8×UInt64, ≤64B body)
  -- without Principal→address mapping. Psy remains Plan fail-closed
  -- (no exact Felt match; PsyFelt-style honesty pin). B-3 research pin still
  -- holds: storage is wire identity leaves, not pubkey/account-id/Field.
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
  expect (prinYul.contents.contains "sload(0)" &&
      prinYul.contents.contains "sload(8)")
    "T10 EVM Principal state must load all 9 leaf slots (0..8)"
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
  -- Psy remains fail-closed on Principal (Felt ≠ wire identity).
  match materializeSelected TargetId.psy prinCompiled with
  | .ok _ =>
      throw <| IO.userError "N2c principal: psy must fail closed on Principal"
  | .error e =>
      expect ((e.render).contains "Principal" ||
          (e.render).contains "principal" ||
          (e.render).contains "unsupported" ||
          (e.render).contains "identity" ||
          (e.render).contains "variable-length" ||
          (e.render).contains "Felt")
        s!"N2c principal psy message must cite Principal boundary, got {e.render}"
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

  -- N-A4: Option state Normalize-admitted. All eight materializers admit
  -- Option UInt64 state (Enum-shaped 2-leaf layout): EVM (BL-31), NEAR
  -- (BL-30), Solana (BL-29), Aleo (BL-35), CosmWasm (BL-33), Psy (BL-36),
  -- Noir (BL-32), TON (BL-34). Quint has no admit path and stays fail closed.
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
  for target in [TargetId.evm, TargetId.solana, TargetId.near] do
    match materializeSelected target commitCompiled with
    | .ok _ => pure ()
    | .error e =>
        throw <| IO.userError s!"N5 commit: {target} must admit Commit identity, got {e.render}"
  for target in [TargetId.noir, TargetId.psy] do
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
  -- B-CTX-OPEN (2026-08-04): EVM (timestamp()) and NEAR (block_timestamp/1e9)
  -- admit unixTimeSeconds; Solana/Noir/Psy keep the fail-closed pin.
  let _ ← liftResult <| materializeSelected TargetId.evm ctxCompiled
  let _ ← liftResult <| materializeSelected TargetId.near ctxCompiled
  for target in [TargetId.solana, TargetId.noir, TargetId.psy] do
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

  -- B-ctx: context.caller (Principal ContextRead) also Plan-fail-closed on
  -- every Phase-1 target (no address/host identity ABI this slice).
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
  for target in [TargetId.evm, TargetId.solana, TargetId.near, TargetId.noir,
      TargetId.psy] do
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

  -- B-RET-ABI: named Struct view return. EVM + Noir + Solana + NEAR + Psy +
  -- CosmWasm + TON admit (multi-leaf ABI: EVM tuple / Noir leaves /
  -- N×8 LE / [Felt; N] / JSON decimals / get-method stack); Aleo admits
  -- non-state entry aggregate returns (native Leo tuple) while
  -- view-over-state stays fail closed.
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
  -- Aleo: view-over-state aggregate return is fail closed via the
  -- computed-view gate (only bare public-state reads map to leo query).
  match materializeSelected TargetId.aleo pairCompiled with
  | .ok _ =>
      throw <| IO.userError "B-RET-ABI: aleo must decline view-over-state aggregate return"
  | .error e =>
      expect ((e.render).contains "leo query" ||
          (e.render).contains "fail closed" ||
          (e.render).contains "aggregate")
        s!"B-RET-ABI aleo message must cite the computed-view/aggregate boundary, got {e.render}"
  -- Aleo admits non-state entry aggregate returns (native Leo tuple).
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


end Tests.Materialization
