import Tests.Fixtures.SourcePrograms
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Core.Semantics
import ProofForgeV2.Examples.Counter
import ProofForgeV2.Language.Loader
import ProofForgeV2.Targets.Registry
import ProofForgeV2.Targets.BuildSelectionV1
import Tests.Language.ParserSession

namespace Tests.Materialization

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Targets.BuildSelectionV1
open Tests.Fixtures.SourcePrograms

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

/-- Characterization helper: target-local resolve→makePlan→lower→emit on bare alpha.
    Product aggregate `materializeResult` accepts only `CompiledProgramV1`. -/
private def materializeAlphaDirect (kind : TargetKind) (descriptor : TargetDescriptor)
    (sem : SemanticProgram) : CompileResult OutputSet := do
  let resolved ← Targets.resolve kind descriptor sem
  match kind with
  | .evm =>
      let plan ← Targets.Evm.makePlan resolved
      let ir ← Targets.Evm.lower plan
      let files ← Targets.Evm.emit ir
      pure (Targets.makeOutput descriptor sem false files)
  | .solana =>
      let plan ← Targets.Solana.makePlan resolved
      let ir ← Targets.Solana.lower plan
      let files ← Targets.Solana.emit ir
      pure (Targets.makeOutput descriptor sem false files)
  | .near =>
      let plan ← Targets.Near.makePlan resolved
      let ir ← Targets.Near.lower plan
      let files ← Targets.Near.emit ir
      pure (Targets.makeOutput descriptor sem false files)
  | .noir =>
      let plan ← Targets.Noir.makePlan resolved
      let ir ← Targets.Noir.lower plan
      let files ← Targets.Noir.emit ir
      pure (Targets.makeOutput descriptor sem false files)
  | other => .error <| .targetNotImplemented other

private def materializeAlphaSelected (target : TargetId) (sem : SemanticProgram) :
    CompileResult OutputSet := do
  let selection ← resolveBuildSelectionV1 target none
  let descriptor ← match Targets.descriptorForKind? selection.kind with
    | some d => pure d
    | none => .error <| .targetNotImplemented selection.kind
  -- Support check mirrors product checkSupport without bare-alpha aggregate.
  Targets.checkSupport selection sem
  materializeAlphaDirect selection.kind descriptor sem

/-- Product aggregate path: CompiledProgramV1 only. -/
private def materializeSelected (target : TargetId) (compiled : CompiledProgramV1)
    (profile? : Option CodegenProfileId := none) : CompileResult OutputSet := do
  let selection ← resolveBuildSelectionV1 target profile?
  Targets.materializeResult selection compiled

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

private partial def nestedSemanticExpr : Nat → Semantic.Expr
  | 0 => .literal 0
  | level + 1 => .checkedAdd (nestedSemanticExpr level) (.literal 0)

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
  let counter ← match Compiler.compile counterQualified with
    | .ok value => pure value
    | .error error => throw <| IO.userError error.render
  let counterWithCall ← match Compiler.compile counterQualifiedWithSynchronousCall with
    | .ok value => pure value
    | .error error => throw <| IO.userError error.render
  let differentLogic ← match Compiler.compile counterQualifiedWithDifferentBusinessLogic with
    | .ok value => pure value
    | .error error => throw <| IO.userError error.render
  let privateSum ← match Compiler.compile privateSum4Qualified with
    | .ok value => pure value
    | .error error => throw <| IO.userError error.render
  let accumulator ← match Compiler.compile accumulatorQualified with
    | .ok value => pure value
    | .error error => throw <| IO.userError error.render
  -- Product dual-carrier path: real ValidatedSourceV1 Counter through aggregate.
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
    expect (!output.files.isEmpty) s!"{target} must emit at least one artifact"
    expect (output.manifest.sourceHash == counterResidual.sourceHash)
      "product manifest must bind ValidatedSourceV1 sourceHash"
    expect (output.manifest.semanticHash == counterResidual.semanticHash)
      "product manifest must bind residual alpha semanticHash"
  -- Characterization four-target path still exercises alpha residual plan/IR.
  for target in [TargetId.evm, TargetId.solana, TargetId.near, TargetId.noir] do
    let output ← liftResult <| materializeAlphaSelected target counter
    expect (!output.files.isEmpty) s!"{target} alpha-direct must emit at least one artifact"
    expect (output.manifest.sourceHash == counterQualified.sourceHash)
      "alpha-direct manifest must bind the decoded source"
    expect (output.manifest.semanticHash == counter.semanticHash)
      "alpha-direct manifest must bind the canonical semantics"
  let noirSel ← liftResult <| resolveBuildSelectionV1 TargetId.noir none
  let unsupported := Targets.checkSupport noirSel counterWithCall
  match unsupported with
  | .error (.unsupportedRequirement .synchronousCall .noir) => pure ()
  | _ => throw <| IO.userError "Noir must reject synchronous chain calls"
  let privateCircuit ← liftResult <| materializeAlphaSelected TargetId.noir privateSum
  expect (privateCircuit.files.any (fun file =>
      file.path == "relations/r0-sum/src/main.nr"))
    "Noir must materialize the private circuit in the same DSL"
  let privateSource ← match privateCircuit.files.find?
      (·.path == "relations/r0-sum/src/main.nr") with
    | some file => pure file.contents
    | none => throw <| IO.userError "PrivateSum4 Noir source is missing"
  expect (privateSource ==
      "fn main(arg_p0: u64, arg_p1: u64, arg_p2: u64, arg_p3: u64, result: pub u64) {\n" ++
      "    let t0: u64 = arg_p0 + arg_p1;\n" ++
      "    let t1: u64 = t0 + arg_p2;\n" ++
      "    let t2: u64 = t1 + arg_p3;\n" ++
      "    assert(result == t2);\n" ++
      "}\n")
    "PrivateSum4 source must keep four private witnesses and one public result"
  let privateInterface ← match privateCircuit.files.find?
      (·.path == "PrivateSum4.noir-relations.json") with
    | some file => pure file.contents
    | none => throw <| IO.userError "PrivateSum4 Noir relation interface is missing"
  for (sourceName, sourceId) in [("a", 0), ("b", 1), ("c", 2), ("d", 3)] do
    expect (privateInterface.contains
        s!"\"sourceName\":\"{sourceName}\",\"sourceId\":{sourceId},\"role\":\"parameter\",\"visibility\":\"private-witness\",\"type\":\"u64\"")
      s!"PrivateSum4 interface must preserve private witness '{sourceName}'"
  expect (privateInterface.contains
      "\"name\":\"result\",\"sourceName\":\"result\",\"sourceId\":null,\"role\":\"result\",\"visibility\":\"public\",\"type\":\"u64\"")
    "PrivateSum4 interface must expose only the declared public result"
  let privateResolved ← liftResult <| Targets.resolve .noir Targets.Noir.descriptor privateSum
  let privatePlan ← liftResult <| Targets.Noir.makePlan privateResolved
  expect (privatePlan.states.isEmpty && privatePlan.continuity == .none &&
      privatePlan.relations.size == 1 && privatePlan.relations[0]!.name == "sum" &&
      (privatePlan.relations[0]!.inputs.take 4).all (·.visibility == .witness) &&
      privatePlan.relations[0]!.inputs[4]!.role == .result &&
      privatePlan.relations[0]!.inputs[4]!.visibility == .verifier)
    "NoirPlan must derive PrivateSum4 witness/public disclosure without a fixture shape"
  let privateIR ← liftResult <| Targets.Noir.lower privatePlan
  expect (privateIR.relations[0]!.operations == #[
      .checkedAdd 0 (.input 0) (.input 1),
      .checkedAdd 1 (.temp 0) (.input 2),
      .checkedAdd 2 (.temp 1) (.input 3),
      .assertEqual (.input 4) (.temp 2)
    ])
    "Noir typed IR must preserve every checked PrivateSum4 addition"
  let evmSelPrivate ← liftResult <| resolveBuildSelectionV1 TargetId.evm none
  match Targets.checkSupport evmSelPrivate privateSum with
  | .error (.unsupportedRequirement .privateWitness .evm) => pure ()
  | _ => throw <| IO.userError "EVM must reject private witness semantics instead of exposing it"
  let accumulatorOutput ← liftResult <| materializeAlphaSelected TargetId.evm accumulator
  let accumulatorResolved ← liftResult <| Targets.resolve .evm Targets.Evm.descriptor accumulator
  let accumulatorPlan ← liftResult <| Targets.Evm.makePlan accumulatorResolved
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
  let futureSchema := { accumulator with schemaVersion := Semantic.schemaVersion + 1 }
  let futureResolved ← liftResult <| Targets.resolve .evm Targets.Evm.descriptor futureSchema
  match Targets.Evm.makePlan futureResolved with
  | .error (.planInvariant .evm _) => pure ()
  | _ => throw <| IO.userError "EVM must reject unknown SemanticProgram schema versions"
  let omittedRequirements := { accumulator with requirements := #[] }
  let omittedRequirementsResolved ←
    liftResult <| Targets.resolve .evm Targets.Evm.descriptor omittedRequirements
  match Targets.Evm.makePlan omittedRequirementsResolved with
  | .error (.planInvariant .evm _) => pure ()
  | _ => throw <| IO.userError "EVM must reject omitted canonical semantic requirements"
  let initializer := accumulator.initializer.get!
  let noncanonicalParam := { initializer.params[0]! with id := ⟨5⟩ }
  let noncanonicalInitializer := {
    initializer with
    params := initializer.params.set! 0 noncanonicalParam
    body := #[.store ⟨0⟩ (.param ⟨5⟩)]
  }
  let noncanonicalProgram := { accumulator with initializer := some noncanonicalInitializer }
  let noncanonicalResolved ← liftResult <| Targets.resolve .evm Targets.Evm.descriptor noncanonicalProgram
  match Targets.Evm.makePlan noncanonicalResolved with
  | .error (.planInvariant .evm _) => pure ()
  | _ => throw <| IO.userError "EVM must reject non-canonical SemanticProgram parameter IDs"
  let deepSemanticEntry := {
    accumulator.entries[0]! with body := #[.returnValue (nestedSemanticExpr 256)]
  }
  let deepSemanticProgram := {
    accumulator with entries := accumulator.entries.set! 0 deepSemanticEntry
  }
  let deepSemanticResolved ← liftResult <| Targets.resolve .evm Targets.Evm.descriptor deepSemanticProgram
  match Targets.Evm.makePlan deepSemanticResolved with
  | .error (.planInvariant .evm _) => pure ()
  | _ => throw <| IO.userError "EVM must reject deep SemanticProgram expressions before lowering"
  let stateWithoutInit := {
    accumulator with
    initializer := none
    requirements := accumulator.requirements
  }
  let stateWithoutInitResolved ← liftResult <| Targets.resolve .evm Targets.Evm.descriptor stateWithoutInit
  match Targets.Evm.makePlan stateWithoutInitResolved with
  | .error (.planInvariant .evm _) => pure ()
  | _ => throw <| IO.userError "EVM must reject stateful programs without an explicit initializer"
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

  let solanaResolved ← liftResult <| Targets.resolve .solana Targets.Solana.descriptor accumulator
  let forgedSolanaProfile ← parseProfileFixture "forged-profile"
  let forgedSolanaDescriptor := {
    Targets.Solana.descriptor with codegenProfile := forgedSolanaProfile
  }
  let forgedSolanaResolved : ResolvedProgram .solana := {
    source := accumulator
    descriptor := forgedSolanaDescriptor
  }
  match Targets.Solana.makePlan forgedSolanaResolved with
  | .error (.planInvariant .solana _) => pure ()
  | _ => throw <| IO.userError "Solana must reject a forged resolved descriptor/profile"
  let solanaPlan ← liftResult <| Targets.Solana.makePlan solanaResolved
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
  let solanaFutureResolved ← liftResult <| Targets.resolve .solana Targets.Solana.descriptor futureSchema
  match Targets.Solana.makePlan solanaFutureResolved with
  | .error (.planInvariant .solana _) => pure ()
  | _ => throw <| IO.userError "Solana must reject unknown SemanticProgram schema versions"
  let solanaOmittedRequirementsResolved ← liftResult <|
    Targets.resolve .solana Targets.Solana.descriptor omittedRequirements
  match Targets.Solana.makePlan solanaOmittedRequirementsResolved with
  | .error (.planInvariant .solana _) => pure ()
  | _ => throw <| IO.userError "Solana must reject omitted canonical semantic requirements"
  let solanaNoncanonicalResolved ← liftResult <|
    Targets.resolve .solana Targets.Solana.descriptor noncanonicalProgram
  match Targets.Solana.makePlan solanaNoncanonicalResolved with
  | .error (.planInvariant .solana _) => pure ()
  | _ => throw <| IO.userError "Solana must reject non-canonical SemanticProgram parameter IDs"
  let solanaStateWithoutInitResolved ← liftResult <|
    Targets.resolve .solana Targets.Solana.descriptor stateWithoutInit
  match Targets.Solana.makePlan solanaStateWithoutInitResolved with
  | .error (.planInvariant .solana _) => pure ()
  | _ => throw <| IO.userError "Solana must reject state-account programs without an initializer"
  let solanaDeepResolved ← liftResult <|
    Targets.resolve .solana Targets.Solana.descriptor deepSemanticProgram
  match Targets.Solana.makePlan solanaDeepResolved with
  | .error (.planInvariant .solana _) => pure ()
  | _ => throw <| IO.userError "Solana must reject deep SemanticProgram expressions before lowering"
  let solanaIR ← liftResult <| Targets.Solana.lower solanaPlan
  expect (solanaIR.handlers[0]!.operations[0]? ==
      some (Targets.Solana.Operation.zeroState 0 8))
    "Solana initializer IR must zero state payload before applying semantic stores"
  let removedChecks := solanaIR.handlers.set! 0 {
    solanaIR.handlers[0]! with checks := #[]
  }
  match Targets.Solana.validateIR { solanaIR with handlers := removedChecks } with
  | .error (.planInvariant .solana _) => pure ()
  | _ => throw <| IO.userError "Solana typed IR must reject missing account/data/init checks"
  let forgedCurrentOperations := #[
    Targets.Solana.Operation.literal 0 99,
    Targets.Solana.Operation.setReturnData 0
  ]
  let forgedCurrentHandler := {
    solanaIR.handlers[2]! with operations := forgedCurrentOperations
  }
  match Targets.Solana.validateIR {
      solanaIR with handlers := solanaIR.handlers.set! 2 forgedCurrentHandler
    } with
  | .error (.planInvariant .solana _) => pure ()
  | _ => throw <| IO.userError "Solana typed IR must remain exactly bound to its source Plan"
  let untouchedState : Semantic.StateDecl := {
    id := ⟨1⟩
    name := "untouched"
    type := .u64
  }
  let partialInitProgram : Semantic.Program := {
    accumulator with
    qualifiedName := "Tests.PartialInit"
    name := "PartialInit"
    «state» := accumulator.state.push untouchedState
  }
  let partialReference ← liftResult <| Semantics.initializeProgram partialInitProgram #[7]
  expect (partialReference.storage == #[7, 0])
    "reference initialization must start every declared state field at zero"
  let partialResolved ← liftResult <|
    Targets.resolve .solana Targets.Solana.descriptor partialInitProgram
  let partialPlan ← liftResult <| Targets.Solana.makePlan partialResolved
  expect (partialPlan.stateAccount.exactDataLen == 24 &&
      partialPlan.stateAccount.initializedMarker == 0x3b1b7ae87b315ebc)
    "Solana layout marker must bind the full two-field account schema"
  let partialIR ← liftResult <| Targets.Solana.lower partialPlan
  expect (partialIR.handlers[0]!.operations[0]? ==
      some (Targets.Solana.Operation.zeroState 0 8) &&
      partialIR.handlers[0]!.operations[1]? ==
        some (Targets.Solana.Operation.zeroState 0 16))
    "Solana initialization must zero every field, including fields omitted by the DSL init body"
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
  let readOtherResolved ← liftResult <|
    Targets.resolve .solana Targets.Solana.descriptor readOtherProgram
  let readOtherPlan ← liftResult <| Targets.Solana.makePlan readOtherResolved
  let readOtherIR ← liftResult <| Targets.Solana.lower readOtherPlan
  expect (readOtherIR.handlers[0]!.operations[0]? ==
      some (Targets.Solana.Operation.zeroState 0 8) &&
      readOtherIR.handlers[0]!.operations[1]? ==
        some (Targets.Solana.Operation.zeroState 0 16) &&
      readOtherIR.handlers[0]!.operations[2]? ==
        some (Targets.Solana.Operation.loadState 0 0 16))
    "Solana initializer must zero all fields before evaluating a state-reading init expression"

  let nearResolved ← liftResult <| Targets.resolve .near Targets.Near.descriptor accumulator
  let forgedNearProfile ← parseProfileFixture "forged-profile"
  let forgedNearDescriptor := {
    Targets.Near.descriptor with codegenProfile := forgedNearProfile
  }
  let forgedNearResolved : ResolvedProgram .near := {
    source := accumulator
    descriptor := forgedNearDescriptor
  }
  match Targets.Near.makePlan forgedNearResolved with
  | .error (.planInvariant .near _) => pure ()
  | _ => throw <| IO.userError "NEAR must reject a forged resolved descriptor/profile"
  let nearPlan ← liftResult <| Targets.Near.makePlan nearResolved
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
  let nearFutureResolved ← liftResult <| Targets.resolve .near Targets.Near.descriptor futureSchema
  match Targets.Near.makePlan nearFutureResolved with
  | .error (.planInvariant .near _) => pure ()
  | _ => throw <| IO.userError "NEAR must reject unknown SemanticProgram schema versions"
  let nearOmittedRequirementsResolved ← liftResult <|
    Targets.resolve .near Targets.Near.descriptor omittedRequirements
  match Targets.Near.makePlan nearOmittedRequirementsResolved with
  | .error (.planInvariant .near _) => pure ()
  | _ => throw <| IO.userError "NEAR must reject omitted canonical semantic requirements"
  let nearNoncanonicalResolved ← liftResult <|
    Targets.resolve .near Targets.Near.descriptor noncanonicalProgram
  match Targets.Near.makePlan nearNoncanonicalResolved with
  | .error (.planInvariant .near _) => pure ()
  | _ => throw <| IO.userError "NEAR must reject non-canonical SemanticProgram parameter IDs"
  let nearStateWithoutInitResolved ← liftResult <|
    Targets.resolve .near Targets.Near.descriptor stateWithoutInit
  match Targets.Near.makePlan nearStateWithoutInitResolved with
  | .error (.planInvariant .near _) => pure ()
  | _ => throw <| IO.userError "NEAR must reject KV-state programs without an initializer"
  let nearDeepResolved ← liftResult <|
    Targets.resolve .near Targets.Near.descriptor deepSemanticProgram
  match Targets.Near.makePlan nearDeepResolved with
  | .error (.planInvariant .near _) => pure ()
  | _ => throw <| IO.userError "NEAR must reject deep SemanticProgram expressions before lowering"

  let nearIR ← liftResult <| Targets.Near.lower nearPlan
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
  match Targets.Near.validateIR {
      nearIR with methods := nearIR.methods.set! 2 forgedNearMethod
    } with
  | .error (.planInvariant .near _) => pure ()
  | _ => throw <| IO.userError "typed NEAR recipe must remain exactly bound to its source Plan"
  let partialNearResolved ← liftResult <|
    Targets.resolve .near Targets.Near.descriptor partialInitProgram
  let partialNearPlan ← liftResult <| Targets.Near.makePlan partialNearResolved
  let partialNearIR ← liftResult <| Targets.Near.lower partialNearPlan
  expect (partialNearIR.methods[0]!.operations[3]? ==
      some (Targets.Near.Operation.zeroState partialNearIR.keys[1]!) &&
      partialNearIR.methods[0]!.operations[4]? ==
        some (Targets.Near.Operation.zeroState partialNearIR.keys[2]!))
    "NEAR initialization must materialize zero for every declared KV field"
  let readOtherNearResolved ← liftResult <|
    Targets.resolve .near Targets.Near.descriptor readOtherProgram
  let readOtherNearPlan ← liftResult <| Targets.Near.makePlan readOtherNearResolved
  let readOtherNearIR ← liftResult <| Targets.Near.lower readOtherNearPlan
  expect (readOtherNearIR.methods[0]!.operations[3]? ==
      some (Targets.Near.Operation.zeroState readOtherNearIR.keys[1]!) &&
      readOtherNearIR.methods[0]!.operations[4]? ==
        some (Targets.Near.Operation.zeroState readOtherNearIR.keys[2]!) &&
      readOtherNearIR.methods[0]!.operations[5]? ==
        some (Targets.Near.Operation.loadState 0 readOtherNearIR.keys[2]!))
    "NEAR initializer must zero all KV fields before an initializer state read"
  let manyNearStates : Array Semantic.StateDecl := (Array.range 11).map fun index => {
    id := ⟨index⟩
    name := s!"field{index}"
    type := .u64
  }
  let manyNearEntry : Semantic.Entry := {
    name := "last"
    params := #[]
    result := .u64
    mode := .view
    body := #[.returnValue (.state ⟨10⟩)]
  }
  let manyNearDraft : Semantic.Program := {
    accumulator with
    qualifiedName := "Tests.ManyNearFields"
    name := "ManyNearFields"
    «state» := manyNearStates
    initializer := some { params := #[], body := #[] }
    entries := #[manyNearEntry]
    requirements := #[]
  }
  let manyNearProgram := {
    manyNearDraft with requirements := Semantic.deriveRequirements manyNearDraft
  }
  let manyNearResolved ← liftResult <|
    Targets.resolve .near Targets.Near.descriptor manyNearProgram
  let manyNearPlan ← liftResult <| Targets.Near.makePlan manyNearResolved
  let manyNearIR ← liftResult <| Targets.Near.lower manyNearPlan
  let lastNearKey := manyNearIR.keys[11]!
  expect (lastNearKey.key == "pf:v1:state:10" && lastNearKey.length == 14)
    "NEAR KV recipe must derive variable key lengths instead of retaining Counter's fixed length"
  let manyNearFiles ← liftResult <| Targets.Near.emit manyNearIR
  let manyNearWat ← match manyNearFiles.find? (·.path == "ManyNearFields.wat") with
    | some file => pure file.contents
    | none => throw <| IO.userError "multi-field NEAR recipe must emit WAT"
  expect (manyNearWat.contains
      s!"(call $pf_storage_read (i64.const 14) (i64.const {lastNearKey.offset})")
    "NEAR WAT must consume the typed key length and offset from its recipe"

  let noirResolved ← liftResult <| Targets.resolve .noir Targets.Noir.descriptor accumulator
  let forgedNoirProfile ← parseProfileFixture "forged-profile"
  let forgedNoirDescriptor := {
    Targets.Noir.descriptor with codegenProfile := forgedNoirProfile
  }
  let forgedNoirResolved : ResolvedProgram .noir := {
    source := accumulator
    descriptor := forgedNoirDescriptor
  }
  match Targets.Noir.makePlan forgedNoirResolved with
  | .error (.planInvariant .noir _) => pure ()
  | _ => throw <| IO.userError "Noir must reject a forged resolved descriptor/profile"
  let noirPlan ← liftResult <| Targets.Noir.makePlan noirResolved
  -- D3 legacy byte-compat: descriptor planHash preimage must match pre-D3
  -- `481f3398` enum/String Repr (not current opaque `{ value := … }` Repr).
  expect (Targets.Noir.targetDescriptorLegacyRepr Targets.Noir.descriptor ==
      noirDescriptorLegacyReprBaseline)
    "Noir descriptor legacy wire must equal independent 481f3398 baseline preimage"
  let opaqueRepr := reprStr Targets.Noir.descriptor
  expect ((opaqueRepr.splitOn "value :=").length > 1)
    "current opaque TargetId Repr still differs from legacy wire (encoder required)"
  expect (noirPlan.planHash == accumulatorPlanHashBaseline)
    "Accumulator Noir planHash must equal independent pre-D3 481f3398 baseline"
  expect (noirPlan.sourceHash == accumulator.sourceHash &&
      noirPlan.semanticHash == accumulator.semanticHash &&
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
  let noirFutureResolved ← liftResult <|
    Targets.resolve .noir Targets.Noir.descriptor futureSchema
  match Targets.Noir.makePlan noirFutureResolved with
  | .error (.planInvariant .noir _) => pure ()
  | _ => throw <| IO.userError "Noir must reject unknown SemanticProgram schema versions"
  let noirOmittedRequirementsResolved ← liftResult <|
    Targets.resolve .noir Targets.Noir.descriptor omittedRequirements
  match Targets.Noir.makePlan noirOmittedRequirementsResolved with
  | .error (.planInvariant .noir _) => pure ()
  | _ => throw <| IO.userError "Noir must reject omitted canonical semantic requirements"
  let noirNoncanonicalResolved ← liftResult <|
    Targets.resolve .noir Targets.Noir.descriptor noncanonicalProgram
  match Targets.Noir.makePlan noirNoncanonicalResolved with
  | .error (.planInvariant .noir _) => pure ()
  | _ => throw <| IO.userError "Noir must reject non-canonical SemanticProgram parameter IDs"
  let noirDeepResolved ← liftResult <|
    Targets.resolve .noir Targets.Noir.descriptor deepSemanticProgram
  match Targets.Noir.makePlan noirDeepResolved with
  | .error (.planInvariant .noir _) => pure ()
  | _ => throw <| IO.userError "Noir must reject deep SemanticProgram expressions before lowering"

  let noirIR ← liftResult <| Targets.Noir.lower noirPlan
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
  match Targets.Noir.validateIR {
      noirIR with relations := noirIR.relations.set! 1 forgedNoirIRRelation
    } with
  | .error (.planInvariant .noir _) => pure ()
  | _ => throw <| IO.userError "typed Noir IR must remain exactly bound to its source Plan"
  let oversizedNoirIRRelation := {
    noirIR.relations[1]! with
    tempCount := noirPlan.resourceLimits.maxIrOperations + 1
  }
  match Targets.Noir.validateIR {
      noirIR with relations := noirIR.relations.set! 1 oversizedNoirIRRelation
    } with
  | .error (.planInvariant .noir _) => pure ()
  | _ => throw <| IO.userError "typed Noir IR must stop at the operation resource limit"
  let deadInitializerArithmetic ← liftResult <| Compiler.compile <| Source.Program.build
    "DeadInitializerArithmetic" #[
      .stateDecl { name := "total", type := .u64 },
      .initializer {
        params := #[{ name := "seed", type := .u64 }]
        body := #[
          .assign "total" (.checkedAdd
            (.literal (UInt64.ofNat 18446744073709551615)) (.literal 1)),
          .assign "total" (.variable "seed")
        ]
      },
      .entry {
        name := "current"
        params := #[]
        result := .u64
        mode := .view
        body := #[.returnValue (.variable "total")]
      }
    ]
  match materializeAlphaSelected TargetId.noir deadInitializerArithmetic with
  | .error (.planInvariant .noir message) =>
      expect (message.contains "dead checked arithmetic")
        "Noir must explain why overwritten initializer arithmetic is rejected"
  | _ => throw <| IO.userError "Noir must reject overwritten initializer arithmetic whose overflow could be eliminated"
  let deadMutationArithmetic ← liftResult <| Compiler.compile <| Source.Program.build
    "DeadMutationArithmetic" #[
      .stateDecl { name := "total", type := .u64 },
      .initializer {
        params := #[{ name := "seed", type := .u64 }]
        body := #[.assign "total" (.variable "seed")]
      },
      .entry {
        name := "overwrite"
        params := #[]
        result := .u64
        mode := .mutate
        body := #[
          .assign "total" (.checkedAdd
            (.literal (UInt64.ofNat 18446744073709551615)) (.literal 1)),
          .assign "total" (.literal 0),
          .returnValue (.literal 0)
        ]
      }
    ]
  match materializeAlphaSelected TargetId.noir deadMutationArithmetic with
  | .error (.planInvariant .noir message) =>
      expect (message.contains "dead checked arithmetic")
        "Noir must explain why overwritten mutate arithmetic is rejected"
  | _ => throw <| IO.userError "Noir must reject overwritten mutate arithmetic whose overflow could be eliminated"

  -- The same supported semantic fragment must compile even when its business
  -- body is not the checked Counter transition.
  let differentOutput ← liftResult <| materializeAlphaSelected TargetId.evm differentLogic
  let differentYul ← match differentOutput.files.find? (·.path == "CounterDifferentLogic.yul") with
    | some file => pure file.contents
    | none => throw <| IO.userError "EVM different-logic program must emit Yul"
  expect (differentYul.contains "let expr0 := 99")
    "EVM lowering must preserve a literal return from SemanticProgram"

  let differentSolanaOutput ← liftResult <| materializeAlphaSelected TargetId.solana differentLogic
  let differentSolanaPlan ← match differentSolanaOutput.files.find?
      (·.path == "CounterDifferentLogic.sbpf-plan") with
    | some file => pure file.contents
    | none => throw <| IO.userError "Solana different-logic program must emit a typed plan"
  expect (differentSolanaPlan.contains "const_u64 99")
    "Solana lowering must preserve a literal return from SemanticProgram"

  let differentNearOutput ← liftResult <| materializeAlphaSelected TargetId.near differentLogic
  let differentNearWat ← match differentNearOutput.files.find?
      (·.path == "CounterDifferentLogic.wat") with
    | some file => pure file.contents
    | none => throw <| IO.userError "NEAR different-logic program must emit WAT"
  expect (differentNearWat.contains "i64.const 99")
    "NEAR lowering must preserve a literal return from SemanticProgram"

  let differentNoirOutput ← liftResult <| materializeAlphaSelected TargetId.noir differentLogic
  let differentNoirMutation ← match differentNoirOutput.files.find?
      (·.path == "relations/r1-increment/src/main.nr") with
    | some file => pure file.contents
    | none => throw <| IO.userError "Noir different-logic program must emit a mutate relation"
  expect (differentNoirMutation.contains "assert(post_s0 == pre_s0);" &&
      differentNoirMutation.contains "assert(result == 99);")
    "Noir lowering must preserve literal return and unchanged state instead of matching Counter"
  expect (differentNoirOutput.files.any
      (·.path == "relations/r2-get/src/main.nr"))
    "Noir lowering must materialize the view relation instead of silently dropping it"

  let nearAccumulator ← liftResult <| materializeAlphaSelected TargetId.near accumulator
  expect (nearAccumulator.files.any (·.path == "Accumulator.wat"))
    "NEAR Accumulator must emit target-derived WAT"
  expect (nearAccumulator.files.any (·.path == "Accumulator.near-abi.json"))
    "NEAR Accumulator must emit target-derived ABI"

  match materializeAlphaSelected TargetId.noir accumulator with
  | .ok output =>
      expect (output.files.any (·.path == "relations/r1-add/src/main.nr") &&
          output.files.any (·.path == "Accumulator.noir-relations.json"))
        "Noir Accumulator must emit a target-owned external-state transition circuit"
  | .error error =>
      throw <| IO.userError s!"Noir must lower Accumulator semantics: {error.render}"

  match materializeAlphaSelected TargetId.solana accumulator with
  | .ok output =>
      expect (output.files.any (·.path == "Accumulator.sbpf-plan"))
        "Solana Accumulator must emit a target-owned typed audit plan"
      expect (output.files.any (·.path == "Accumulator.idl.json"))
        "Solana Accumulator must emit a target-derived IDL"
  | .error error =>
      throw <| IO.userError s!"Solana must lower Accumulator semantics: {error.render}"

end Tests.Materialization
