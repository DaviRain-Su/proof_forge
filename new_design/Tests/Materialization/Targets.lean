import ProofForgeV2.Examples.Counter
import ProofForgeV2.Examples.Accumulator
import ProofForgeV2.Examples.PrivateSum4
import ProofForgeV2.Compiler.Pipeline
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

  -- The same supported semantic fragment must compile even when its business
  -- body is not the checked Counter transition.
  let differentOutput ← Targets.materialize .evm differentLogic
  let differentYul ← match differentOutput.files.find? (·.path == "CounterDifferentLogic.yul") with
    | some file => pure file.contents
    | none => throw <| IO.userError "EVM different-logic program must emit Yul"
  expect (differentYul.contains "let expr0 := 99")
    "EVM lowering must preserve a literal return from SemanticProgram"

  for target in [TargetId.solana, .near, .noir] do
    match Targets.materializeResult target differentLogic with
    | .error (.planInvariant rejectedTarget _) =>
        expect (rejectedTarget == target) "shape rejection must identify its target"
    | _ => throw <| IO.userError s!"{target} must reject lookalike programs with different business logic"

  for target in [TargetId.solana, .near, .noir] do
    match Targets.materializeResult target accumulator with
    | .error (.planInvariant rejectedTarget _) =>
        expect (rejectedTarget == target) "unsupported Accumulator target must identify itself"
    | _ => throw <| IO.userError s!"{target} is not yet generalized for Accumulator"

end Tests.Materialization
