import ProofForgeV2.Examples.StateCell
import ProofForgeV2.Targets.Solana
import ProofForgeV2.Targets.BuildSelectionV1
import ProofForgeV2.Targets.Registry
import ProofForgeV2.Language.Loader
import Tests.Language.ParserSession

namespace Tests.Materialization.SolanaStaticAlignmentV1

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Semantic.WireV1
open ProofForgeV2.Targets.BuildSelectionV1
open ProofForgeV2.Targets.Solana

private def uint64Type : TypeDeclV1 := {
  id := 0
  name := none
  shape := .uint 64
}

private def countState : StateDeclV1 := {
  id := 0
  name := "count"
  typeId := 0
  visibility := .public_
}

private def data : SemanticProgramDataV1 := {
  qualifiedName := {
    components := ⟨"Tests", #["SolanaStaticAlignmentV1"]⟩
  }
  types := #[uint64Type]
  constants := #[]
  logicalState := #[countState]
  events := #[]
  errors := #[]
  callables := #[]
  invariants := #[]
  requirements := { items := #[] }
}

private def countField : StateField := {
  sourceId := 0
  name := "count"
  accountIndex := 0
  byteOffset := 8
  byteWidth := 8
  endianness := .little
}

private def stateAccount : StateAccount := {
  index := 0
  name := "state"
  ownerPolicy := .currentProgram
  exactDataLen := 16
  headerOffset := 0
  headerWidth := 8
  initializedMarker := 846264958600013564
  payloadInitialization := .zeroAllFields
  fields := #[countField]
  stateLeaves := #[#[0]]
  admitProductExternalCall := true
}

private def getDiscriminator : String := "a4a276b0d690dd37"

private def getHandler : Handler := {
  name := "get"
  discriminator := getDiscriminator
  params := #[]
  mode := .view
  resultKind := .u64
  accountAccess := {
    accountIndex := 0
    ownerPolicy := .currentProgram
    exactDataLen := 16
    signerRequired := false
    writableRequired := false
    initialization := .mustBeInitialized
  }
  body := #[.returnValue (.stateLoad 0 8)]
}

private def plan : Plan := {
  (default : Plan) with
  stateAccount
  entries := #[getHandler]
}

private def getHandlerIR : HandlerIR := {
  name := "get"
  discriminator := getDiscriminator
  params := #[]
  mode := .view
  resultKind := .u64
  accountAccess := getHandler.accountAccess
  checks := #[
    .numAccounts 1,
    .accountNonDuplicate 0,
    .instructionDataLen 8,
    .ownerCurrentProgram 0,
    .accountDataLen 0 16,
    .headerEquals 0 0 stateAccount.initializedMarker
  ]
  operations := #[
    .loadState 0 0 8,
    .setReturnData 8 0
  ]
}

private def binding : UInt64StateAccountBindingV1 := {
  semanticStateId := 0
  semanticTypeId := 0
  stateName := "count"
  physicalFieldIndex := 0
  accountIndex := 0
  byteOffset := 8
}

private theorem alignment :
    NullaryUInt64ViewStaticAlignmentV1 data plan binding "get"
      getDiscriminator getHandler getHandlerIR := by
  apply nullaryUInt64ViewStaticAlignmentV1_of_recognized
  · simp [UInt64StateAccountBindingRelV1, data, plan, binding, uint64Type,
      countState, stateAccount, countField]
  · rfl
  · rfl
  · rfl
  · rfl
  · decide
  · rfl
  · rfl

private def accountData (value : UInt64) : ByteArray :=
  oneFieldUInt64AccountDataV1 stateAccount.initializedMarker value

private theorem accountData_size (value : UInt64) :
    (accountData value).size = plan.stateAccount.exactDataLen := by
  exact oneFieldUInt64AccountDataV1_size _ _

private theorem accountData_header (value : UInt64) :
    readUInt64LEV1 (accountData value) plan.stateAccount.headerOffset =
      some plan.stateAccount.initializedMarker := by
  exact readUInt64LEV1_oneFieldUInt64AccountDataV1_header _ _

private theorem accountData_field (value : UInt64) :
    readUInt64LEV1 (accountData value) binding.byteOffset = some value := by
  exact readUInt64LEV1_oneFieldUInt64AccountDataV1_field _ _

private theorem initializedAccountRel (value : UInt64) :
    InitializedUInt64AccountRelV1 plan binding #[encodeU64le value]
      (encodeU64le value) (accountData value) value := by
  exact ⟨rfl, rfl, accountData_size value, accountData_header value,
    accountData_field value⟩

example (discriminatorValue value : UInt64)
    (hdiscriminator :
      discriminatorToLeU64V1 getDiscriminator = .ok discriminatorValue) :
    executeHandlerIRV1 getHandlerIR
      (nullaryUInt64ViewInvocationV1 (accountData value)
        discriminatorValue) =
      .returned (some (encodeU64le value)) := by
  exact executeHandlerIRV1_of_nullaryUInt64ViewStaticAlignment data plan
    binding "get" getDiscriminator getHandler getHandlerIR (accountData value)
    discriminatorValue value alignment hdiscriminator
    (accountData_size value)
    (accountData_header value) (accountData_field value)

example (discriminatorValue otherDiscriminator value : UInt64)
    (hdiscriminator :
      discriminatorToLeU64V1 getDiscriminator = .ok discriminatorValue)
    (hne : otherDiscriminator ≠ discriminatorValue) :
    executeHandlerIRV1 getHandlerIR
      (nullaryUInt64ViewInvocationV1 (accountData value) otherDiscriminator) =
      .trapped .discriminatorMismatch := by
  exact executeHandlerIRV1_of_nullaryUInt64ViewStaticAlignment_wrong_discriminator
    data plan binding "get" getDiscriminator getHandler getHandlerIR
    (accountData value) discriminatorValue otherDiscriminator alignment
    hdiscriminator hne

example (discriminatorValue value : UInt64)
    (hdiscriminator :
      discriminatorToLeU64V1 getDiscriminator = .ok discriminatorValue) :
    executeHandlerIRV1 getHandlerIR
      (nullaryUInt64ViewInvocationV1 (accountData value)
        discriminatorValue false) =
      .trapped .ownerMismatch := by
  exact executeHandlerIRV1_of_nullaryUInt64ViewStaticAlignment_wrong_owner
    data plan binding "get" getDiscriminator getHandler getHandlerIR
    (accountData value) discriminatorValue alignment hdiscriminator

example (discriminatorValue value : UInt64)
    (hdiscriminator :
      discriminatorToLeU64V1 getDiscriminator = .ok discriminatorValue) :
    executeHandlerIRV1 getHandlerIR
      (nullaryUInt64ViewInvocationV1 (accountData value)
        discriminatorValue true true) =
      .trapped .duplicateAccount := by
  exact executeHandlerIRV1_of_nullaryUInt64ViewStaticAlignment_duplicate
    data plan binding "get" getDiscriminator getHandler getHandlerIR
    (accountData value) discriminatorValue alignment hdiscriminator

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def liftResult (result : CompileResult α) : IO α :=
  match result with
  | .ok value => pure value
  | .error error => throw <| IO.userError error.render

private unsafe def compileStateCell
    (session : Language.Loader.ParserSession) : IO CompiledSemanticV1 := do
  let validated ← liftResult (← session.selectProgramV1
    ProofForgeV2.Examples.stateCellSourceText "<solana-static-alignment>"
    ProofForgeV2.Examples.stateCellModuleNameV1 none)
  liftResult <| Compiler.compileValidatedSourceV1 validated

private def stateCellCapability (compiled : CompiledSemanticV1) :
    CompileResult Targets.ResolvedEngineeringBuildV1 := do
  let selection ← resolveBuildSelectionV1 TargetId.solana
    (some CodegenProfileId.solanaSbpfCpiElfV1)
  Targets.resolveEngineeringRequirementsV1 selection compiled

/-- Exercise the real StateCell capability→Plan→HandlerIR graph. The
    compile-time theorems above classify and execute the same exact recipe. -/
private unsafe def testProductionStateCell
    (session : Language.Loader.ParserSession) : IO Unit := do
  let compiled ← compileStateCell session
  let capability ← liftResult <| stateCellCapability compiled
  let productionPlan ← liftResult <|
    materializeFullBodyPlanForProductV1 capability false
  let productionIR ← liftResult <|
    fullBodyIrFromProductCapabilityV1 capability false
  liftResult <| validatePlan productionPlan
  liftResult <| validateIR productionIR
  let some productionGet := productionPlan.entries.find? (·.name == "get")
    | throw <| IO.userError "StateCell production Plan has no get handler"
  let some productionGetIR := productionIR.handlers.find? (·.name == "get")
    | throw <| IO.userError "StateCell production IR has no get handler"
  expect (productionPlan.stateAccount == stateAccount)
    s!"StateCell production account layout left the bounded one-field layout:\n{repr productionPlan.stateAccount}"
  expect (productionGet == getHandler)
    s!"StateCell production get Plan recipe left the bounded alignment shape:\n{repr productionGet}"
  expect (productionGetIR == getHandlerIR)
    s!"StateCell production get HandlerIR left the bounded alignment shape:\n{repr productionGetIR}"
  expect (recognizeNullaryUInt64ViewHandlerV1 productionGet).isSome
    "production StateCell.get Plan handler was not recognized"
  expect (recognizeNullaryUInt64ViewHandlerIRV1 productionGetIR).isSome
    "production StateCell.get HandlerIR was not recognized"
  let discriminatorValue ← liftResult <|
    discriminatorToLeU64V1 productionGetIR.discriminator
  let bytes := oneFieldUInt64AccountDataV1
    productionPlan.stateAccount.initializedMarker 42
  let invocation := nullaryUInt64ViewInvocationV1 bytes discriminatorValue
  let observed := observeHandlerIRV1 productionGetIR invocation
  expect (observed.outcome ==
        .returned (some (encodeU64le 42)))
    "production StateCell.get did not return the exact account UInt64"
  expect (observed.postAccounts == invocation.accounts)
    "production StateCell.get changed the read-only account observation"
  expect (executeHandlerIRV1 productionGetIR
      (nullaryUInt64ViewInvocationV1 bytes 0) ==
        .trapped .discriminatorMismatch)
    "production StateCell.get accepted a mismatched discriminator"
  expect (executeHandlerIRV1 productionGetIR
      (nullaryUInt64ViewInvocationV1 bytes discriminatorValue false) ==
        .trapped .ownerMismatch)
    "production StateCell.get accepted a wrong-owner account"
  expect (executeHandlerIRV1 productionGetIR
      (nullaryUInt64ViewInvocationV1 bytes discriminatorValue true true) ==
        .trapped .duplicateAccount)
    "production StateCell.get accepted a duplicate account row"
  let wrongHeader := oneFieldUInt64AccountDataV1 0 42
  expect (executeHandlerIRV1 productionGetIR
      (nullaryUInt64ViewInvocationV1 wrongHeader discriminatorValue) ==
        .trapped .headerMismatch)
    "production StateCell.get accepted an uninitialized account header"

unsafe def run : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  testProductionStateCell session
  IO.println "solana-static-alignment-v1: ok"

end Tests.Materialization.SolanaStaticAlignmentV1
