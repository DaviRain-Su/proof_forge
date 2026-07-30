import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Compiler.AlphaCompatibility
import ProofForgeV2.Core.Crypto
import ProofForgeV2.Core.Semantics
import ProofForgeV2.Examples.Counter
import ProofForgeV2.Language.Loader
import ProofForgeV2.Targets.Registry
import ProofForgeV2.Targets.BuildSelectionV1
import ProofForgeV2.Targets.RequirementResolverV1
import ProofForgeV2.Semantic.RequirementsV1
import ProofForgeV2.Semantic.WireV1
import Tests.Fixtures.SourcePrograms
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

private def planSolana (compiled : CompiledSemanticV1) : CompileResult Targets.Solana.Plan := do
  let selection ← resolveBuildSelectionV1 TargetId.solana none
  let capability ← Targets.resolveEngineeringRequirementsV1 selection compiled
  Targets.Solana.planFromCapability capability

private def planNear (compiled : CompiledSemanticV1) : CompileResult Targets.Near.Plan := do
  let selection ← resolveBuildSelectionV1 TargetId.near none
  let capability ← Targets.resolveEngineeringRequirementsV1 selection compiled
  Targets.Near.planFromCapability capability

private def planNoir (compiled : CompiledSemanticV1) : CompileResult Targets.Noir.Plan := do
  let selection ← resolveBuildSelectionV1 TargetId.noir none
  let capability ← Targets.resolveEngineeringRequirementsV1 selection compiled
  Targets.Noir.planFromCapability capability

/-- Capability-gated production IR inspection (S6 repair; not TargetIrFixtures). -/
private def irEvm (compiled : CompiledSemanticV1) : CompileResult Targets.Evm.IR := do
  let selection ← resolveBuildSelectionV1 TargetId.evm none
  let capability ← Targets.resolveEngineeringRequirementsV1 selection compiled
  Targets.Evm.irFromCapability capability

private def irSolana (compiled : CompiledSemanticV1) : CompileResult Targets.Solana.IR := do
  let selection ← resolveBuildSelectionV1 TargetId.solana none
  let capability ← Targets.resolveEngineeringRequirementsV1 selection compiled
  Targets.Solana.irFromCapability capability

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
    renderer). Trailing newline is part of the hashed bytes. -/
private def accumulatorNearWatExactUtf8Len : Nat := 4918
private def accumulatorNearWatSha256Hex : String :=
  "14223fa01511215995ff82a7ab0cffa7484a537d51c7c86ff8250cd12f3b99c0"

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
        .store { accountIndex := 0, byteOffset := 16, value := .param 16 }])
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
        .store { fieldIndex := 1, value := .param 8 }])
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
        .store { fieldIndex := 1, value := .param 2 }])
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
        (.checkedSub 7 5 6 solana.arithmeticOverflowError))
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

-- Fast regression for the frozen four-target retained-V1 UInt64 add/sub seam.
set_option maxRecDepth 10000 in
unsafe def runSemanticPlanLeafFast : IO Unit := do
  testSemanticPlanSourceAuthority
  testRichUInt64SemanticPlans

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
  "  executionHost := ProofForgeV2.ExecutionHost.circuit,\n" ++
  "  commitModel := ProofForgeV2.CommitModel.externalStateTransition,\n" ++
  "  stateBinding := ProofForgeV2.StateBinding.proofInputs,\n" ++
  "  callModel := ProofForgeV2.CallModel.none,\n" ++
  "  proofModel := ProofForgeV2.ProofModel.circuitProof,\n" ++
  "  settlementModel := ProofForgeV2.SettlementModel.externalVerifier,\n" ++
  "  codegenProfile := \"noir-source-u64-relations-v1\" }"

/-- Independent single-semantic-carrier Accumulator Noir planHash golden. -/
private def accumulatorPlanHashBaseline : String :=
  "1bd35ab0daa2cacb39e7a3aea9ae7d3be4d06c3a186a351ddf655ec19a886143"

set_option maxRecDepth 10000 in
unsafe def run : IO Unit := do
  runSemanticPlanLeafFast
  -- Product path: real ValidatedSourceV1 Counter through the capability aggregate.
  -- All four target Plan bodies consume retained SemanticProgramV1 S1; residual-only
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
  -- Synchronous-call / privateWitness: product support inspection (not residual planFromAlpha).
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
  let syncCallReq : RequirementRequestV1 := {
    id := "effect.synchronous-call"
    version := s2RequirementVersionV1
    digest := zeroDigest
    predicates := #[]
  }
  match inspectResolveRequestsV1 evmSupport.supported { items := #[syncCallReq] } with
  | .error e =>
      expect (e.code == "PF-REQ-UNSUPPORTED")
        s!"EVM product support must reject synchronous-call, got {e.render}"
  | .ok _ =>
      throw <| IO.userError "EVM must reject synchronous-call on product support inspection"
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
    Targets.Solana.Operation.setReturnData 0
  ]
  let forgedCurrentHandler := {
    solanaIR.handlers[2]! with operations := forgedCurrentOperations
  }
  match Targets.Solana.validateIR
      (Targets.Solana.withHandlers solanaIR
        (solanaIR.handlers.set! 2 forgedCurrentHandler)) with
  | .error (.planInvariant .solana _) => pure ()
  | _ => throw <| IO.userError "Solana typed IR must remain exactly bound to its source Plan"
  -- S1 still excludes multi-field partial-init/read-other shapes. Keep this
  -- legacy Core.Semantics characterization explicit and isolated from the
  -- ProgramV1 compiled carrier.
  let legacyAccumulator ← liftResult <|
    Compiler.AlphaCompatibility.compile Tests.Fixtures.SourcePrograms.accumulatorQualified
  let untouchedState : Semantic.StateDecl := {
    id := ⟨1⟩
    name := "untouched"
    type := .u64
  }
  let partialInitProgram : Semantic.Program := {
    legacyAccumulator with
    qualifiedName := "Tests.PartialInit"
    name := "PartialInit"
    «state» := legacyAccumulator.state.push untouchedState
  }
  let partialReference ← liftResult <| Semantics.initializeProgram partialInitProgram #[7]
  expect (partialReference.storage == #[7, 0])
    "reference initialization must start every declared state field at zero"
  let readOtherInitializer : Semantic.Initializer := {
    params := #[]
    body := #[.store ⟨0⟩ (.state ⟨1⟩)]
  }
  let readOtherDraft := {
    partialInitProgram with
    qualifiedName := "Tests.ReadOtherInit"
    name := "ReadOtherInit"
    initializer := some readOtherInitializer
    requirements := #[]
  }
  let readOtherProgram := {
    readOtherDraft with requirements := Semantic.deriveRequirements readOtherDraft
  }
  let readOtherReference ← liftResult <| Semantics.initializeProgram readOtherProgram #[]
  expect (readOtherReference.storage == #[0, 0])
    "reference initializer state reads must observe canonical zero storage"

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
  expect (nearPlan.hostImports.size == 7 &&
      nearPlan.hostImports.contains .attachedDeposit &&
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
      .setReturnData 3
    ])
    "NEAR mutable recipe must preserve checked Accumulator statement order"
  expect (nearIR.methods[2]!.operations == #[
      .checkInputLen 0,
      .requireLayout nearMarker nearPlan.storage.markerValue,
      .loadState 0 nearField,
      .setReturnData 0
    ])
    "NEAR view recipe must require empty input/layout and contain no deposit or write operation"
  let forgedNearOperations := #[
    Targets.Near.Operation.checkInputLen 0,
    .requireLayout nearMarker nearPlan.storage.markerValue,
    .literal 0 99,
    .setReturnData 0
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
  -- Transitional descriptor preimage must be explicit and independent of opaque
  -- structure Repr; requirement support is not part of this identity.
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

end Tests.Materialization
