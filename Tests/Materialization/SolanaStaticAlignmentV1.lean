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

private def unitType : TypeDeclV1 := {
  id := 1
  name := none
  shape := .unit
}

private def initialParam : Param := {
  sourceId := 0
  name := "initial"
  dataOffset := 8
  byteWidth := 8
  endianness := .little
}

private def deltaParam : Param := {
  sourceId := 0
  name := "delta"
  dataOffset := 8
  byteWidth := 8
  endianness := .little
}

private def initializeDiscriminator : String :=
  instructionDiscriminator "initialize" #[initialParam]

private def incrementDiscriminator : String :=
  instructionDiscriminator "increment" #[deltaParam]

private def initializeCallable : CallableV1 := {
  id := 0
  kind := .initializer
  name := none
  params := #[{
    valueId := 0
    name := "initial"
    typeId := 0
    visibility := .public_
  }]
  result := {
    typeId := 1
    visibility := .public_
  }
  entryBlock := 0
  blocks := #[{
    id := 0
    params := #[]
    instructions := #[{
      result := none
      op := .stateStore 0 0
    }]
    terminator := .return_ none
  }]
  loopBounds := #[]
  invariantSteps := none
}

private def incrementCallable : CallableV1 := {
  id := 1
  kind := .entry
  name := some "increment"
  params := #[{
    valueId := 0
    name := "delta"
    typeId := 0
    visibility := .public_
  }]
  result := {
    typeId := 0
    visibility := .public_
  }
  entryBlock := 0
  blocks := #[{
    id := 0
    params := #[]
    instructions := #[
      {
        result := some { valueId := 1, typeId := 0 }
        op := .stateLoad 0
      },
      {
        result := some { valueId := 2, typeId := 0 }
        op := .binary .add 1 0
      },
      {
        result := none
        op := .stateStore 0 2
      },
      {
        result := some { valueId := 3, typeId := 0 }
        op := .stateLoad 0
      }
    ]
    terminator := .return_ (some 3)
  }]
  loopBounds := #[]
  invariantSteps := none
}

private def alignedData : SemanticProgramDataV1 := {
  data with
  types := #[uint64Type, unitType]
  callables := #[initializeCallable, incrementCallable]
}

private def initializeHandler : Handler := {
  name := "initialize"
  discriminator := initializeDiscriminator
  params := #[initialParam]
  mode := .initialize
  resultKind := .u64
  accountAccess := {
    accountIndex := 0
    ownerPolicy := .currentProgram
    exactDataLen := 16
    signerRequired := true
    writableRequired := true
    initialization := .mustBeUninitialized
  }
  body := #[
    .store { accountIndex := 0, byteOffset := 8, value := .param 8 },
    .returnNone
  ]
}

private def incrementHandler : Handler := {
  name := "increment"
  discriminator := incrementDiscriminator
  params := #[deltaParam]
  mode := .mutate
  resultKind := .u64
  accountAccess := {
    accountIndex := 0
    ownerPolicy := .currentProgram
    exactDataLen := 16
    signerRequired := false
    writableRequired := true
    initialization := .mustBeInitialized
  }
  body := #[
    .store {
      accountIndex := 0
      byteOffset := 8
      value := .checkedAdd (.stateLoad 0 8) (.param 8)
    },
    .returnValue (.stateLoad 0 8)
  ]
}

private def mutatingPlan : Plan := {
  plan with
  arithmeticOverflowError := arithmeticOverflowError
  initializer := initializeHandler
  entries := #[incrementHandler, getHandler]
}

private def initializeHandlerIR : HandlerIR := {
  name := "initialize"
  discriminator := initializeDiscriminator
  params := #[initialParam]
  mode := .initialize
  resultKind := .u64
  accountAccess := initializeHandler.accountAccess
  checks := #[
    .numAccounts 1,
    .accountNonDuplicate 0,
    .instructionDataLen 16,
    .ownerCurrentProgram 0,
    .accountDataLen 0 16,
    .signer 0,
    .writable 0,
    .headerEquals 0 0 0
  ]
  operations := #[
    .zeroState 0 8,
    .loadParam 0 8,
    .storeState 0 8 0,
    .setHeader 0 0 stateAccount.initializedMarker
  ]
}

private def incrementHandlerIR : HandlerIR := {
  name := "increment"
  discriminator := incrementDiscriminator
  params := #[deltaParam]
  mode := .mutate
  resultKind := .u64
  accountAccess := incrementHandler.accountAccess
  checks := #[
    .numAccounts 1,
    .accountNonDuplicate 0,
    .instructionDataLen 16,
    .ownerCurrentProgram 0,
    .accountDataLen 0 16,
    .writable 0,
    .headerEquals 0 0 stateAccount.initializedMarker
  ]
  operations := #[
    .loadState 0 0 8,
    .loadParam 1 8,
    .checkedAdd 2 0 1 arithmeticOverflowError,
    .storeState 0 8 2,
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

private theorem initializeAlignment :
    UnaryUInt64InitializerStaticAlignmentV1 alignedData mutatingPlan binding
      0 1 0 "initial" initializeDiscriminator initializeHandler
      initializeHandlerIR := by
  refine {
    bindingRel := ?_
    stateZero := rfl
    unitType := rfl
    callableExact := rfl
    parameterZero := rfl
    stateAccountIndex := rfl
    accountZero := rfl
    stateAccountOwner := rfl
    headerWidth := rfl
    headerDistinct := by decide
    handlerExact := rfl
    handlerIRExact := rfl
  }
  simp [UInt64StateAccountBindingRelV1, alignedData, data, mutatingPlan,
    plan, binding, uint64Type, countState, stateAccount, countField]

private theorem incrementAlignment :
    UnaryUInt64CheckedAddStaticAlignmentV1 alignedData mutatingPlan binding
      1 0 "increment" "delta" incrementDiscriminator incrementHandler
      incrementHandlerIR := by
  refine {
    bindingRel := ?_
    stateZero := rfl
    callableExact := rfl
    parameterZero := rfl
    stateAccountIndex := rfl
    accountZero := rfl
    stateAccountOwner := rfl
    headerWidth := rfl
    headerDistinct := by decide
    overflowCode := rfl
    handlerExact := rfl
    handlerIRExact := rfl
  }
  simp [UInt64StateAccountBindingRelV1, alignedData, data, mutatingPlan,
    plan, binding, uint64Type, countState, stateAccount, countField]

example :
    isSupportedUnaryUInt64InitializerHandlerIRV1 initializeHandlerIR = true :=
  isSupportedUnaryUInt64InitializerHandlerIRV1_of_alignment alignedData
    mutatingPlan binding 0 1 0 "initial" initializeDiscriminator
    initializeHandler initializeHandlerIR initializeAlignment

example :
    isSupportedUnaryUInt64CheckedAddHandlerIRV1 incrementHandlerIR = true :=
  isSupportedUnaryUInt64CheckedAddHandlerIRV1_of_alignment alignedData
    mutatingPlan binding 1 0 "increment" "delta" incrementDiscriminator
    incrementHandler incrementHandlerIR incrementAlignment

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
  let semanticData ←
    match validateSemanticProgramV1 (CompiledSemanticV1.semanticV1Of compiled) with
    | .ok value => pure value
    | .error error => throw <| IO.userError s!"semantic validation failed: {repr error}"
  let capability ← liftResult <| stateCellCapability compiled
  let productionPlan ← liftResult <|
    materializeFullBodyPlanForProductV1 capability false
  let productionIR ← liftResult <|
    fullBodyIrFromProductCapabilityV1 capability false
  liftResult <| validatePlan productionPlan
  liftResult <| validateIR productionIR
  let some productionGet := productionPlan.entries.find? (·.name == "get")
    | throw <| IO.userError "StateCell production Plan has no get handler"
  let productionInitialize := productionPlan.initializer
  let some productionIncrement :=
      productionPlan.entries.find? (·.name == "increment")
    | throw <| IO.userError "StateCell production Plan has no increment handler"
  let some productionGetIR := productionIR.handlers.find? (·.name == "get")
    | throw <| IO.userError "StateCell production IR has no get handler"
  let some productionInitializeIR :=
      productionIR.handlers.find? (·.name == "initialize")
    | throw <| IO.userError "StateCell production IR has no initialize handler"
  let some productionIncrementIR :=
      productionIR.handlers.find? (·.name == "increment")
    | throw <| IO.userError "StateCell production IR has no increment handler"
  expect (productionPlan.stateAccount == stateAccount)
    s!"StateCell production account layout left the bounded one-field layout:\n{repr productionPlan.stateAccount}"
  expect (productionGet == getHandler)
    s!"StateCell production get Plan recipe left the bounded alignment shape:\n{repr productionGet}"
  expect (productionInitialize == initializeHandler)
    s!"StateCell production initialize Plan recipe left the bounded alignment shape:\n{repr productionInitialize}"
  expect (productionIncrement == incrementHandler)
    s!"StateCell production increment Plan recipe left the bounded alignment shape:\n{repr productionIncrement}"
  expect (productionGetIR == getHandlerIR)
    s!"StateCell production get HandlerIR left the bounded alignment shape:\n{repr productionGetIR}"
  expect (productionInitializeIR == initializeHandlerIR)
    s!"StateCell production initialize HandlerIR left the bounded alignment shape:\n{repr productionInitializeIR}"
  expect (productionIncrementIR == incrementHandlerIR)
    s!"StateCell production increment HandlerIR left the bounded alignment shape:\n{repr productionIncrementIR}"
  expect (semanticData.types[0]? == some uint64Type &&
      semanticData.types[1]? == some unitType)
    "StateCell production type rows left the bounded alignment shape"
  expect (semanticData.callables[0]? == some initializeCallable)
    "StateCell production initializer callable left the bounded alignment shape"
  expect (semanticData.callables[1]? == some incrementCallable)
    "StateCell production increment callable left the bounded alignment shape"
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
  let wrongDiscriminatorOutcome := executeHandlerIRV1 productionGetIR
    (nullaryUInt64ViewInvocationV1 bytes 0)
  expect (wrongDiscriminatorOutcome == .trapped .discriminatorMismatch)
    s!"production StateCell.get mismatched-discriminator outcome: {repr wrongDiscriminatorOutcome}"
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

  let initializeDiscriminator ← liftResult <|
    discriminatorToLeU64V1 productionInitializeIR.discriminator
  let uninitializedBytes := oneFieldUInt64AccountDataV1 0 999
  let initializeInvocation := unaryUInt64InvocationV1 uninitializedBytes
    initializeDiscriminator 41 true true
  let initialized := observeHandlerIRV1 productionInitializeIR initializeInvocation
  expect (initialized.outcome == .returned none)
    "production StateCell.initialize did not return successfully"
  expect (initialized.postAccounts[0]?.map (·.data) == some
      (oneFieldUInt64AccountDataV1
        productionPlan.stateAccount.initializedMarker 41))
    "production StateCell.initialize did not write the marker and initial value"
  expect (executeHandlerIRV1 productionInitializeIR
      (unaryUInt64InvocationV1 uninitializedBytes initializeDiscriminator 41
        false true) == .trapped .signerRequired)
    "production StateCell.initialize accepted a missing signer"
  expect (executeHandlerIRV1 productionInitializeIR
      (unaryUInt64InvocationV1 bytes initializeDiscriminator 41 true true) ==
        .trapped .headerMismatch)
    "production StateCell.initialize accepted an initialized account"

  let incrementDiscriminator ← liftResult <|
    discriminatorToLeU64V1 productionIncrementIR.discriminator
  let incrementInvocation := unaryUInt64InvocationV1 bytes
    incrementDiscriminator 8 false true
  let incremented := observeHandlerIRV1 productionIncrementIR incrementInvocation
  expect (incremented.outcome == .returned (some (encodeU64le 50)))
    "production StateCell.increment did not return the checked sum"
  expect (incremented.postAccounts[0]?.map (·.data) == some
      (oneFieldUInt64AccountDataV1
        productionPlan.stateAccount.initializedMarker 50))
    "production StateCell.increment did not commit the checked sum"
  expect (executeHandlerIRV1 productionIncrementIR
      (unaryUInt64InvocationV1 bytes incrementDiscriminator 8 false false) ==
        .trapped .writableRequired)
    "production StateCell.increment accepted a read-only account"

  let overflowBytes := oneFieldUInt64AccountDataV1
    productionPlan.stateAccount.initializedMarker 0xffffffffffffffff
  let overflowInvocation := unaryUInt64InvocationV1 overflowBytes
    incrementDiscriminator 1 false true
  let overflowed := observeHandlerIRV1 productionIncrementIR overflowInvocation
  expect (overflowed.outcome ==
      .trapped (.arithmeticOverflow arithmeticOverflowError))
    "production StateCell.increment did not trap on UInt64 overflow"
  expect (overflowed.postAccounts == overflowInvocation.accounts)
    "production StateCell.increment committed state after overflow"

  let missingInitializeOperation := {
    productionInitializeIR with
    operations := productionInitializeIR.operations.pop
  }
  expect (executeHandlerIRV1 missingInitializeOperation initializeInvocation ==
      .trapped .unsupportedHandlerShape)
    "initializer with a missing production operation did not fail closed"
  let tamperedIncrement := {
    productionIncrementIR with
    operations := productionIncrementIR.operations.set! 2
      (.checkedAdd 2 0 1 7)
  }
  expect (executeHandlerIRV1 tamperedIncrement incrementInvocation ==
      .trapped .unsupportedHandlerShape)
    "increment with a tampered overflow code did not fail closed"
  let missingIncrementCheck := {
    productionIncrementIR with
    checks := productionIncrementIR.checks.pop
  }
  expect (executeHandlerIRV1 missingIncrementCheck incrementInvocation ==
      .trapped .unsupportedHandlerShape)
    "increment with a missing production check did not fail closed"

unsafe def run : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  testProductionStateCell session
  IO.println "solana-static-alignment-v1: ok"

end Tests.Materialization.SolanaStaticAlignmentV1
