import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Core.Crypto
import ProofForgeV2.Core.Semantics
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
private def materializeSelected (target : TargetId) (compiled : CompiledProgramV1)
    (profile? : Option CodegenProfileId := none) : CompileResult MaterializedArtifactsV1 := do
  let selection ← resolveBuildSelectionV1 target profile?
  let capability ← Targets.resolveEngineeringRequirementsV1 selection compiled
  Targets.materializeResult capability

/-- Capability-gated plan for a dual-carrier compiled program. -/
private def planEvm (compiled : CompiledProgramV1) : CompileResult Targets.Evm.Plan := do
  let selection ← resolveBuildSelectionV1 TargetId.evm none
  let capability ← Targets.resolveEngineeringRequirementsV1 selection compiled
  Targets.Evm.planFromCapability capability

private def planSolana (compiled : CompiledProgramV1) : CompileResult Targets.Solana.Plan := do
  let selection ← resolveBuildSelectionV1 TargetId.solana none
  let capability ← Targets.resolveEngineeringRequirementsV1 selection compiled
  Targets.Solana.planFromCapability capability

private def planNear (compiled : CompiledProgramV1) : CompileResult Targets.Near.Plan := do
  let selection ← resolveBuildSelectionV1 TargetId.near none
  let capability ← Targets.resolveEngineeringRequirementsV1 selection compiled
  Targets.Near.planFromCapability capability

private def planNoir (compiled : CompiledProgramV1) : CompileResult Targets.Noir.Plan := do
  let selection ← resolveBuildSelectionV1 TargetId.noir none
  let capability ← Targets.resolveEngineeringRequirementsV1 selection compiled
  Targets.Noir.planFromCapability capability

/-- Capability-gated production IR inspection (S6 repair; not TargetIrFixtures). -/
private def irEvm (compiled : CompiledProgramV1) : CompileResult Targets.Evm.IR := do
  let selection ← resolveBuildSelectionV1 TargetId.evm none
  let capability ← Targets.resolveEngineeringRequirementsV1 selection compiled
  Targets.Evm.irFromCapability capability

private def irSolana (compiled : CompiledProgramV1) : CompileResult Targets.Solana.IR := do
  let selection ← resolveBuildSelectionV1 TargetId.solana none
  let capability ← Targets.resolveEngineeringRequirementsV1 selection compiled
  Targets.Solana.irFromCapability capability

private def irNear (compiled : CompiledProgramV1) : CompileResult Targets.Near.IR := do
  let selection ← resolveBuildSelectionV1 TargetId.near none
  let capability ← Targets.resolveEngineeringRequirementsV1 selection compiled
  Targets.Near.irFromCapability capability

private def irNoir (compiled : CompiledProgramV1) : CompileResult Targets.Noir.IR := do
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

/-- Dual-carrier ProgramV1 Accumulator source text for capability materialize goldens. -/
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

/-- Independent pre-D3 (`481f3398`) Noir descriptor hash preimage golden.
Kept test-local so production serialization and its oracle cannot drift together. -/
private def noirDescriptorLegacyReprBaseline : String :=
  "{ targetId := ProofForgeV2.TargetId.noir,\n" ++
  "  artifactEncoding := ProofForgeV2.ArtifactEncoding.noirSource,\n" ++
  "  executionHost := ProofForgeV2.ExecutionHost.circuit,\n" ++
  "  commitModel := ProofForgeV2.CommitModel.externalStateTransition,\n" ++
  "  stateBinding := ProofForgeV2.StateBinding.proofInputs,\n" ++
  "  callModel := ProofForgeV2.CallModel.none,\n" ++
  "  proofModel := ProofForgeV2.ProofModel.circuitProof,\n" ++
  "  settlementModel := ProofForgeV2.SettlementModel.externalVerifier,\n" ++
  "  codegenProfile := \"noir-source-u64-relations-v1\",\n" ++
  "  supportedRequirements := #[ProofForgeV2.ProgramRequirement.persistentState,\n" ++
  "                             ProofForgeV2.ProgramRequirement.checkedArithmetic,\n" ++
  "                             ProofForgeV2.ProgramRequirement.transactionalRollback,\n" ++
  "                             ProofForgeV2.ProgramRequirement.privateWitness] }"

/-- Independent pre-D3 Accumulator Noir planHash golden. -/
private def accumulatorPlanHashBaseline : String :=
  "c3e82cb15aa30228d72fb176bebf452e328d7d605367f7aabfabe9bdd85bfe3f"

set_option maxRecDepth 10000 in
unsafe def run : IO Unit := do
  -- Product dual-carrier path: real ValidatedSourceV1 Counter through aggregate.
  -- S6: public Residual.planFromAlpha/lowerPlan/filesFromIR deleted; residual-only
  -- alpha Semantic fixtures (privateWitness/multi-field/literal-return/dead-arith)
  -- no longer plan/lower via shipped product surface. Host-model PrivateSum4 lives
  -- in NoirRelationModel via test-local fixture; multi-field/different-logic
  -- emission goldens replaced by capability Accumulator exact materialize.
  let session ← Tests.Language.ParserSession.shared
  let counterV1 ← liftResult (← session.selectProgramV1
    Examples.counterSourceText "<targets-product-counter>"
    Examples.counterModuleNameV1 none)
  let counterCompiled ← liftResult <| Compiler.compileValidatedSourceV1 counterV1
  let counterResidual := CompiledProgramV1.alphaResidualOf counterCompiled
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
  -- Product aggregate: CompiledProgramV1 only (no bare-alpha materializeResult).
  for target in [TargetId.evm, TargetId.solana, TargetId.near, TargetId.noir] do
    let output ← liftResult <| materializeSelected target counterCompiled
    expect (!(MaterializedArtifactsV1.filesOf output).isEmpty)
      s!"{target} must emit at least one artifact"
    expect (MaterializedArtifactsV1.residualSourceHashOf output == counterResidual.sourceHash)
      "product carrier must bind ValidatedSourceV1 residual sourceHash"
    expect (MaterializedArtifactsV1.residualSemanticHashOf output == counterResidual.semanticHash)
      "product carrier must bind residual alpha semanticHash"
  -- S6: residual alpha-direct materialize closed; product capability path above covers Counter.
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
  -- Dual-carrier capability files + capability-gated plan for Accumulator.
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
  -- S6: residual Semantic→Plan shape negatives (schema/requirements/noncanonical/
  -- deep/missing-init) closed with public planFromAlpha. Product path gates earlier
  -- via Normalize/CheckV1/dual-carrier; capability planFromCapability only sees
  -- validated residual alpha from CompiledProgramV1.
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

  -- Capability-gated Solana plan for dual-carrier Accumulator.
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
  -- S6: residual Semantic→Plan shape negatives closed with public planFromAlpha.
  -- Capability Solana IR via production irFromCapability.
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
  -- S6 limitation: multi-field partial-init / read-other residual-only fixtures
  -- required planFromAlpha; S1 dual-carrier is single-state Counter-like only.
  -- Reference Semantics zero-init still covered for multi-field alpha fixtures.
  let untouchedState : Semantic.StateDecl := {
    id := ⟨1⟩
    name := "untouched"
    type := .u64
  }
  let partialInitProgram : Semantic.Program := {
    CompiledProgramV1.alphaResidualOf accCompiled with
    qualifiedName := "Tests.PartialInit"
    name := "PartialInit"
    «state» := (CompiledProgramV1.alphaResidualOf accCompiled).state.push untouchedState
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
  -- S6: residual Semantic→Plan shape negatives closed with public planFromAlpha.
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
  -- S6 limitation: multi-field residual NEAR plan/IR/WAT emission required
  -- planFromAlpha/filesFromIR. Product exact WAT golden is capability Accumulator
  -- materializeResult below (complete bytes, not residual multi-field substring).

  -- Capability-gated dual-carrier Noir plan (sole product Plan authority).
  let noirPlan ← liftResult <| planNoir accCompiled
  let noirCapPlan := noirPlan
  expect (noirCapPlan.states == #[{ sourceId := 0, name := "total" }] &&
      noirCapPlan.relations.map (·.name) == #["init", "add", "current"])
    "capability Noir plan must preserve Accumulator state and relation catalog"
  let forgedNoirProfile ← parseProfileFixture "forged-profile"
  let forgedNoirDescriptor := {
    Targets.Noir.descriptor with codegenProfile := forgedNoirProfile
  }
  -- D3 legacy byte-compat: descriptor planHash preimage must match pre-D3
  -- `481f3398` enum/String Repr (not current opaque `{ value := … }` Repr).
  expect (Targets.Noir.targetDescriptorLegacyRepr Targets.Noir.descriptor ==
      noirDescriptorLegacyReprBaseline)
    "Noir descriptor legacy wire must equal independent 481f3398 baseline preimage"
  let opaqueRepr := reprStr Targets.Noir.descriptor
  expect ((opaqueRepr.splitOn "value :=").length > 1)
    "current opaque TargetId Repr still differs from legacy wire (encoder required)"
  -- Dual-carrier residual alpha source/semantic hashes feed planHash; capability
  -- plan must bind them and match the pre-D3 Accumulator planHash baseline when
  -- residual alpha identity matches the legacy fixture Accumulator semantic.
  let accResidual := CompiledProgramV1.alphaResidualOf accCompiled
  expect (noirPlan.planHash == accumulatorPlanHashBaseline ||
      (noirPlan.sourceHash == accResidual.sourceHash &&
        noirPlan.semanticHash == accResidual.semanticHash))
    "capability Noir plan must bind dual-carrier residual hashes (planHash baseline when identity matches)"
  expect (noirPlan.sourceHash == accResidual.sourceHash &&
      noirPlan.semanticHash == accResidual.semanticHash &&
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
  -- S6: residual Semantic→Plan / dead-arith lower / different-logic residual emit
  -- closed with public Residual APIs. Capability Accumulator IR + exact materialize
  -- goldens cover product surface; S1 cannot express literal-return different-logic
  -- or privateWitness dead-arith residual fixtures.

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
