import ProofForgeV2.Examples.Counter
import ProofForgeV2.Examples.Accumulator
import ProofForgeV2.Examples.PrivateSum4
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Core.Semantics
import ProofForgeV2.Targets.Registry

namespace Tests.Materialization

open ProofForgeV2

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def liftResult (result : CompileResult α) : IO α :=
  match result with
  | .ok value => pure value
  | .error error => throw <| IO.userError error.render

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

def run : IO Unit := do
  let counter ← match Compiler.compile Examples.counter with
    | .ok value => pure value
    | .error error => throw <| IO.userError error.render
  let counterWithCall ← match Compiler.compile Examples.counterWithSynchronousCall with
    | .ok value => pure value
    | .error error => throw <| IO.userError error.render
  let differentLogic ← match Compiler.compile Examples.counterWithDifferentBusinessLogic with
    | .ok value => pure value
    | .error error => throw <| IO.userError error.render
  let privateSum ← match Compiler.compile Examples.privateSum4 with
    | .ok value => pure value
    | .error error => throw <| IO.userError error.render
  let accumulator ← match Compiler.compile Examples.accumulator with
    | .ok value => pure value
    | .error error => throw <| IO.userError error.render
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
  for target in [TargetId.evm, .solana, .near, .noir] do
    let output ← Targets.materialize target counter
    expect (!output.files.isEmpty) s!"{target} must emit at least one artifact"
    expect (output.manifest.sourceHash == Examples.counter.sourceHash)
      "manifest must bind the decoded source"
    expect (output.manifest.semanticHash == counter.semanticHash)
      "manifest must bind the canonical semantics"
  let unsupported := Targets.checkSupport .noir counterWithCall
  match unsupported with
  | .error (.unsupportedRequirement .synchronousCall .noir) => pure ()
  | _ => throw <| IO.userError "Noir must reject synchronous chain calls"
  let privateCircuit ← Targets.materialize .noir privateSum
  expect (privateCircuit.files.any (fun file => file.path == "src/main.nr"))
    "Noir must materialize the private circuit in the same DSL"
  match Targets.checkSupport .evm privateSum with
  | .error (.unsupportedRequirement .privateWitness .evm) => pure ()
  | _ => throw <| IO.userError "EVM must reject private witness semantics instead of exposing it"
  let accumulatorOutput ← Targets.materialize .evm accumulator
  let accumulatorResolved ← liftResult <| Targets.resolve Targets.Evm.descriptor accumulator
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
  let futureResolved ← liftResult <| Targets.resolve Targets.Evm.descriptor futureSchema
  match Targets.Evm.makePlan futureResolved with
  | .error (.planInvariant .evm _) => pure ()
  | _ => throw <| IO.userError "EVM must reject unknown SemanticProgram schema versions"
  let omittedRequirements := { accumulator with requirements := #[] }
  let omittedRequirementsResolved ←
    liftResult <| Targets.resolve Targets.Evm.descriptor omittedRequirements
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
  let noncanonicalResolved ← liftResult <| Targets.resolve Targets.Evm.descriptor noncanonicalProgram
  match Targets.Evm.makePlan noncanonicalResolved with
  | .error (.planInvariant .evm _) => pure ()
  | _ => throw <| IO.userError "EVM must reject non-canonical SemanticProgram parameter IDs"
  let deepSemanticEntry := {
    accumulator.entries[0]! with body := #[.returnValue (nestedSemanticExpr 256)]
  }
  let deepSemanticProgram := {
    accumulator with entries := accumulator.entries.set! 0 deepSemanticEntry
  }
  let deepSemanticResolved ← liftResult <| Targets.resolve Targets.Evm.descriptor deepSemanticProgram
  match Targets.Evm.makePlan deepSemanticResolved with
  | .error (.planInvariant .evm _) => pure ()
  | _ => throw <| IO.userError "EVM must reject deep SemanticProgram expressions before lowering"
  let stateWithoutInit := {
    accumulator with
    initializer := none
    requirements := accumulator.requirements
  }
  let stateWithoutInitResolved ← liftResult <| Targets.resolve Targets.Evm.descriptor stateWithoutInit
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

  let solanaResolved ← liftResult <| Targets.resolve Targets.Solana.descriptor accumulator
  let forgedSolanaDescriptor := {
    Targets.Solana.descriptor with codegenProfile := "forged-profile"
  }
  let forgedSolanaResolved : ResolvedProgram .solana := {
    source := accumulator
    descriptor := forgedSolanaDescriptor
    targetMatches := rfl
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
  let solanaFutureResolved ← liftResult <| Targets.resolve Targets.Solana.descriptor futureSchema
  match Targets.Solana.makePlan solanaFutureResolved with
  | .error (.planInvariant .solana _) => pure ()
  | _ => throw <| IO.userError "Solana must reject unknown SemanticProgram schema versions"
  let solanaOmittedRequirementsResolved ← liftResult <|
    Targets.resolve Targets.Solana.descriptor omittedRequirements
  match Targets.Solana.makePlan solanaOmittedRequirementsResolved with
  | .error (.planInvariant .solana _) => pure ()
  | _ => throw <| IO.userError "Solana must reject omitted canonical semantic requirements"
  let solanaNoncanonicalResolved ← liftResult <|
    Targets.resolve Targets.Solana.descriptor noncanonicalProgram
  match Targets.Solana.makePlan solanaNoncanonicalResolved with
  | .error (.planInvariant .solana _) => pure ()
  | _ => throw <| IO.userError "Solana must reject non-canonical SemanticProgram parameter IDs"
  let solanaStateWithoutInitResolved ← liftResult <|
    Targets.resolve Targets.Solana.descriptor stateWithoutInit
  match Targets.Solana.makePlan solanaStateWithoutInitResolved with
  | .error (.planInvariant .solana _) => pure ()
  | _ => throw <| IO.userError "Solana must reject state-account programs without an initializer"
  let solanaDeepResolved ← liftResult <|
    Targets.resolve Targets.Solana.descriptor deepSemanticProgram
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
    Targets.resolve Targets.Solana.descriptor partialInitProgram
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
    Targets.resolve Targets.Solana.descriptor readOtherProgram
  let readOtherPlan ← liftResult <| Targets.Solana.makePlan readOtherResolved
  let readOtherIR ← liftResult <| Targets.Solana.lower readOtherPlan
  expect (readOtherIR.handlers[0]!.operations[0]? ==
      some (Targets.Solana.Operation.zeroState 0 8) &&
      readOtherIR.handlers[0]!.operations[1]? ==
        some (Targets.Solana.Operation.zeroState 0 16) &&
      readOtherIR.handlers[0]!.operations[2]? ==
        some (Targets.Solana.Operation.loadState 0 0 16))
    "Solana initializer must zero all fields before evaluating a state-reading init expression"

  -- The same supported semantic fragment must compile even when its business
  -- body is not the checked Counter transition.
  let differentOutput ← Targets.materialize .evm differentLogic
  let differentYul ← match differentOutput.files.find? (·.path == "CounterDifferentLogic.yul") with
    | some file => pure file.contents
    | none => throw <| IO.userError "EVM different-logic program must emit Yul"
  expect (differentYul.contains "let expr0 := 99")
    "EVM lowering must preserve a literal return from SemanticProgram"

  let differentSolanaOutput ← Targets.materialize .solana differentLogic
  let differentSolanaPlan ← match differentSolanaOutput.files.find?
      (·.path == "CounterDifferentLogic.sbpf-plan") with
    | some file => pure file.contents
    | none => throw <| IO.userError "Solana different-logic program must emit a typed plan"
  expect (differentSolanaPlan.contains "const_u64 99")
    "Solana lowering must preserve a literal return from SemanticProgram"

  for target in [TargetId.near, .noir] do
    match Targets.materializeResult target differentLogic with
    | .error (.planInvariant rejectedTarget _) =>
        expect (rejectedTarget == target) "shape rejection must identify its target"
    | _ => throw <| IO.userError s!"{target} must reject lookalike programs with different business logic"

  for target in [TargetId.near, .noir] do
    match Targets.materializeResult target accumulator with
    | .error (.planInvariant rejectedTarget _) =>
        expect (rejectedTarget == target) "unsupported Accumulator target must identify itself"
    | _ => throw <| IO.userError s!"{target} is not yet generalized for Accumulator"

  match Targets.materializeResult .solana accumulator with
  | .ok output =>
      expect (output.files.any (·.path == "Accumulator.sbpf-plan"))
        "Solana Accumulator must emit a target-owned typed audit plan"
      expect (output.files.any (·.path == "Accumulator.idl.json"))
        "Solana Accumulator must emit a target-derived IDL"
  | .error error =>
      throw <| IO.userError s!"Solana must lower Accumulator semantics: {error.render}"

end Tests.Materialization
