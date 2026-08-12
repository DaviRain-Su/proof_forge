import Examples.VerifiedVaultPF
import ProofForgeV2.Semantic.PreservationShapeV1
import ProofForgeV2.Targets.Near.WATSemanticsV1

namespace Tests.Materialization.NearStaticAlignmentV1

open ProofForgeV2.Semantic.InvariantABI
open ProofForgeV2.Semantic.PreservationShapeV1
open ProofForgeV2.Semantic.ReferenceV1
open ProofForgeV2.Semantic.WireV1
open ProofForgeV2.Targets.Near

private def data : SemanticProgramDataV1 :=
  Examples.VerifiedVaultPF.Proof.subjectDataV1

private def subjectProgram : SemanticProgramV1 :=
  Examples.VerifiedVaultPF.Proof.subjectProgramV1

private def reservesKey : String := "pf:test:vault:reserves"
private def sharesKey : String := "pf:test:vault:shares"

private def storage : StorageLayout := {
  markerKey := layoutMarkerKey
  markerValue := 1
  payloadInitialization := .zeroAllFields
  fields := #[
    {
      sourceId := 0
      name := "reserves"
      key := reservesKey
      byteWidth := 8
      endianness := .little
    },
    {
      sourceId := 1
      name := "shares"
      key := sharesKey
      byteWidth := 8
      endianness := .little
    }
  ]
  stateLeaves := #[#[0], #[1]]
}

private def reservesBinding : UInt64StateBindingV1 := {
  semanticStateId := 0
  semanticTypeId := 0
  semanticName := "reserves"
  physicalFieldIndex := 0
  physicalKey := reservesKey
}

private def sharesBinding : UInt64StateBindingV1 := {
  semanticStateId := 1
  semanticTypeId := 0
  semanticName := "shares"
  physicalFieldIndex := 1
  physicalKey := sharesKey
}

private def nonCoincidentData : SemanticProgramDataV1 := {
  data with
  types := #[
    { id := 0, name := none, shape := .uint 64 },
    { id := 1, name := none, shape := .option 0 }
  ]
  logicalState := #[
    { id := 0, name := "maybe", typeId := 1, visibility := .public_ },
    { id := 1, name := "later", typeId := 0, visibility := .public_ }
  ]
}

private def nonCoincidentFields : Array StorageField := #[
  {
    sourceId := 0
    name := "maybe_tag"
    key := stateKey 0
    byteWidth := 8
    endianness := .little
  },
  {
    sourceId := 1
    name := "maybe_value"
    key := stateKey 1
    byteWidth := 8
    endianness := .little
  },
  {
    sourceId := 2
    name := "later"
    key := stateKey 2
    byteWidth := 8
    endianness := .little
  }
]

private def nonCoincidentStorage : StorageLayout := {
  markerKey := layoutMarkerKey
  markerValue := layoutMarker nonCoincidentFields
  payloadInitialization := .zeroAllFields
  fields := nonCoincidentFields
  stateLeaves := #[#[0, 1], #[2]]
}

private def semanticSourcedStorage : StorageLayout := {
  nonCoincidentStorage with
  fields := #[
    nonCoincidentFields[0]!,
    nonCoincidentFields[1]!,
    {
      sourceId := 1
      name := "later"
      key := stateKey 2
      byteWidth := 8
      endianness := .little
    }
  ]
}

private def nonCoincidentBinding : UInt64StateBindingV1 := {
  semanticStateId := 1
  semanticTypeId := 0
  semanticName := "later"
  physicalFieldIndex := 2
  physicalKey := stateKey 2
}

private def tenBytes : ByteArray := encodeU64le 10

private def logicalTen : LogicalStateV1 := {
  initialized := true
  canonicalValues :=
    ((encodeU32le 8).append tenBytes).append
      ((encodeU32le 8).append tenBytes)
}

private def logicalZero : LogicalStateV1 := {
  initialized := true
  canonicalValues :=
    ((encodeU32le 8).append (encodeU64le 0)).append
      ((encodeU32le 8).append (encodeU64le 0))
}

private def uint64Type : TypeDeclV1 := {
  id := 0
  name := none
  shape := .uint 64
}

private def reservesDecl : StateDeclV1 := {
  id := 0
  name := "reserves"
  typeId := 0
  visibility := .public_
}

private def sharesDecl : StateDeclV1 := {
  id := 1
  name := "shares"
  typeId := 0
  visibility := .public_
}

private theorem tenBytes_size : tenBytes.size = 8 := by
  exact encodeU64le_size 10

private theorem tenBytes_canonical :
    validateValueBytesV1 data.types 0 tenBytes = .ok () := by
  exact validateValueBytesV1_uint64_of_size data.types 0 uint64Type tenBytes
    (by rfl) (by rfl) tenBytes_size

private theorem logicalTen_encoded :
    encodeLogicalStateValuesV1 data true #[tenBytes, tenBytes] =
      .ok logicalTen := by
  simpa [logicalTen, doubleUint64CanonicalV1, ByteArray.append_assoc] using
    (encodeLogicalStateValuesV1_double_uint64_eq_ok data
      reservesDecl sharesDecl tenBytes tenBytes true
      (by rfl) tenBytes_canonical tenBytes_canonical
      tenBytes_size tenBytes_size)

private theorem logicalTen_decoded :
    decodeLogicalStateValuesV1 data logicalTen =
      .ok #[tenBytes, tenBytes] := by
  exact decodeLogicalStateValuesV1_of_encodeLogicalStateValuesV1
    data true #[tenBytes, tenBytes] logicalTen logicalTen_encoded

private theorem logicalZero_encoded :
    encodeLogicalStateValuesV1 data true #[encodeU64le 0, encodeU64le 0] =
      .ok logicalZero := by
  have hcanonical :
      validateValueBytesV1 data.types 0 (encodeU64le 0) = .ok () :=
    validateValueBytesV1_uint64_of_size data.types 0 uint64Type
      (encodeU64le 0) (by rfl) (by rfl) (encodeU64le_size 0)
  simpa [logicalZero, doubleUint64CanonicalV1, ByteArray.append_assoc] using
    (encodeLogicalStateValuesV1_double_uint64_eq_ok data reservesDecl sharesDecl
      (encodeU64le 0) (encodeU64le 0) true (by rfl) hcanonical hcanonical
      (encodeU64le_size 0) (encodeU64le_size 0))

private def observedStorage : StorageObservationV1 := {
  lookup := fun key =>
    if key == layoutMarkerKey then some (encodeU64le storage.markerValue)
    else if key == reservesKey then some tenBytes
    else if key == sharesKey then some tenBytes
    else none
}

private def markerOnlyStorage : StorageObservationV1 := {
  lookup := fun key =>
    if key == layoutMarkerKey then some (encodeU64le storage.markerValue)
    else none
}

private def emptyStorage : StorageObservationV1 := {
  lookup := fun _ => none
}

private def markerRegion : KeyRegion := {
  key := layoutMarkerKey
  offset := 0
  length := layoutMarkerKey.toUTF8.size
}

private def reservesRegion : KeyRegion := {
  key := reservesKey
  offset := markerRegion.length
  length := reservesKey.toUTF8.size
}

private def sharesRegion : KeyRegion := {
  key := sharesKey
  offset := markerRegion.length + reservesRegion.length
  length := sharesKey.toUTF8.size
}

private def statusMemory : MemoryLayout := {
  minPages := 1
  inputOffset := 1024
  inputCapacity := 1024
  depositOffset := 2048
  valueOffset := 4096
}

private def initMethod : Method := {
  name := "init"
  params := #[]
  exactInputLen := 0
  mode := .initialize
  depositPolicy := .requireZero
  resultKind := .unit
  body := #[
    .store { fieldIndex := 0, value := .literal 0, byteWidth := 8 },
    .store { fieldIndex := 1, value := .literal 0, byteWidth := 8 },
    .returnNone
  ]
}

private def initIR : MethodIR := {
  name := "init"
  params := #[]
  mode := .initialize
  tempCount := 2
  operations := #[
    .checkInputLen 0,
    .requireZeroAttachedDeposit,
    .requireLayoutAbsent markerRegion,
    .zeroState reservesRegion,
    .zeroState sharesRegion,
    .literal 0 0,
    .storeState reservesRegion 0,
    .literal 1 0,
    .storeState sharesRegion 1,
    .setLayout markerRegion storage.markerValue
  ]
}

private def initTypedWAT : Array MethodWATInstructionV1 :=
  nullaryZeroTwoUInt64InitializerWATV1 canonicalRegisters statusMemory
    markerRegion reservesRegion sharesRegion storage.markerValue

private def initializedZeroStorage : StorageObservationV1 :=
  zeroTwoUInt64InitializerPostStorageV1 emptyStorage markerRegion reservesRegion
    sharesRegion storage.markerValue

private theorem initAlignment :
    NullaryZeroTwoUInt64InitializerStaticAlignmentV1 data storage reservesBinding
      sharesBinding "init" initMethod markerRegion reservesRegion sharesRegion
        initIR := by
  constructor <;>
    simp [UInt64StateBindingRelV1, data,
      Examples.VerifiedVaultPF.Proof.subjectDataV1, storage, reservesBinding,
      sharesBinding, initMethod, initIR, markerRegion, reservesRegion,
      sharesRegion, reservesKey, sharesKey]

private theorem initTypedWATLowering :
    lowerMethodWATOperationsV1 canonicalRegisters statusMemory
      initIR.operations = some initTypedWAT := by
  exact lowerMethodWATOperationsV1_nullaryZeroTwoUInt64Initializer
    canonicalRegisters statusMemory markerRegion reservesRegion sharesRegion
      storage.markerValue

private def statusMethod : Method := {
  name := "status"
  params := #[]
  exactInputLen := 0
  mode := .view
  depositPolicy := .queryOnly
  resultKind := .uint64
  body := #[.returnValue (.stateLoad 0)]
}

private def statusCallable : CallableV1 := {
  id := 3
  kind := .view
  name := some "status"
  params := #[]
  result := { typeId := 0, visibility := .public_ }
  entryBlock := 0
  blocks := #[{
    id := 0
    params := #[]
    instructions := #[{
      result := some { valueId := 0, typeId := 0 }
      op := .stateLoad 0
    }]
    terminator := .return_ (some 0)
  }]
  loopBounds := #[]
  invariantSteps := none
}

private theorem statusDirectInvocationContextFreeV1 :
    directInvocationContextFreeV1 statusCallable = true := by
  simp [directInvocationContextFreeV1, statusCallable]

private theorem verifiedVaultStatusReady :
    ∃ admitted : AdmittedReferenceSliceV1,
      admitReferenceProgramSliceV1 subjectProgram = .ok admitted ∧
        admitted.data = data ∧
          gateInvocation admitted logicalTen {
            callableId := 3
            args := #[]
            context := #[]
          } = .ready statusCallable #[tenBytes, tenBytes] #[] false := by
  have hvalidate : validateSemanticProgramV1 subjectProgram = .ok data := by
    exact Examples.VerifiedVaultPF.Proof.subjectValidationOkV1
  have hadmission : validateReferenceProgramDataAdmissionV1 data = .ok () := by
    change validateReferenceProgramDataAdmissionV1
      (ProofForgeV2.Semantic.InitializerDepositWithdrawViewEqualitySubjectV1.subjectDataV1
        Examples.VerifiedVaultPF.Proof.subjectDataV1.qualifiedName
        "reserves" "shares" "deposit" "amount" "withdraw" "amount"
        "status" "solvent") = .ok ()
    exact
      ProofForgeV2.Semantic.InitializerDepositWithdrawViewEqualitySubjectV1.referenceAdmissionV1
        Examples.VerifiedVaultPF.Proof.subjectDataV1.qualifiedName
        "reserves" "shares" "deposit" "amount" "withdraw" "amount"
        "status" "solvent"
  obtain ⟨admitted, hadmit⟩ :=
    admitReferenceProgramSliceV1_exists_of_checks subjectProgram data hvalidate
      hadmission
  have hadmitted :=
    admitReferenceProgramSliceV1_ok_implies subjectProgram data admitted hvalidate
      hadmit
  have hinitial :=
    initialLogicalStateV1_double_uint64_eq_ok subjectProgram data reservesDecl
      sharesDecl uint64Type true hvalidate (by rfl) (by rfl) (by rfl)
      (by rfl)
      (by
        simp [data, Examples.VerifiedVaultPF.Proof.subjectDataV1]
        exact Or.inl rfl)
      (by rfl) (by rfl)
  have hconforms : StateConformsV1 subjectProgram logicalTen :=
    stateConformsV1_intro_of_validate_eq_ok subjectProgram data logicalTen
      #[tenBytes, tenBytes] hvalidate rfl logicalTen_decoded
  have hlookup :
      admitted.data.callables[statusCallable.id.toNat]? =
        some statusCallable := by
    rw [hadmitted.2]
    rfl
  have hcontext :
      emptyInvocationContextAcceptedV1 admitted.data statusCallable = true := by
    exact
      emptyInvocationContextAcceptedV1_of_directInvocationContextFreeV1
        admitted.data statusCallable hlookup statusDirectInvocationContextFreeV1
  refine ⟨admitted, hadmit, hadmitted.2, ?_⟩
  simpa [statusCallable] using
    gateInvocation_ready_nullary_view_of_checksV1 admitted logicalTen
      statusCallable #[tenBytes, tenBytes] _ hlookup (by rfl) (by rfl)
      hcontext (by simpa [hadmitted.1] using hinitial) rfl
      (by simpa [StateConformsV1, hadmitted.1] using hconforms)
      (by simpa [hadmitted.2] using logicalTen_decoded)

private def statusIR : MethodIR := {
  name := "status"
  params := #[]
  mode := .view
  tempCount := 1
  operations := #[
    .checkInputLen 0,
    .requireLayout markerRegion storage.markerValue,
    .loadState 0 reservesRegion,
    .setReturnData 8 0
  ]
}

private def statusTypedWAT : Array ReadOnlyWATInstructionV1 :=
  nullaryUInt64ViewWATV1 canonicalRegisters statusMemory markerRegion
    storage.markerValue reservesRegion

private theorem statusTypedWATLowering :
    lowerReadOnlyWATOperationsV1 canonicalRegisters statusMemory
      statusIR.operations = some statusTypedWAT := by
  rfl

private def statusMethodShape : NullaryUInt64ViewMethodShapeV1 := {
  viewName := "status"
  physicalFieldIndex := 0
}

private def statusMethodIRShape : NullaryUInt64ViewMethodIRShapeV1 := {
  viewName := "status"
  markerRegion
  markerValue := storage.markerValue
  fieldRegion := reservesRegion
}

private def successfulObservation : CallObservationV1 := {
  exportName := "status"
  input := ByteArray.empty
  returnData := some tenBytes
  failureObserved := false
  logs := #[]
  promises := #[]
  preStorage := observedStorage
  postStorage := observedStorage
}

private def wrongReturnObservation : CallObservationV1 := {
  successfulObservation with returnData := some (encodeU64le 11)
}

private def failedObservation : CallObservationV1 := {
  exportName := "withdraw"
  input := encodeU64le 11
  returnData := none
  failureObserved := true
  logs := #[]
  promises := #[]
  preStorage := observedStorage
  postStorage := observedStorage
}

private theorem reservesBinding_rel :
    UInt64StateBindingRelV1 data storage reservesBinding := by
  simp [UInt64StateBindingRelV1, data,
    Examples.VerifiedVaultPF.Proof.subjectDataV1, storage, reservesBinding]

private theorem statusAlignment :
    NullaryUInt64ViewStaticAlignmentV1 data storage reservesBinding "status"
      statusMethod markerRegion reservesRegion statusIR := by
  simp [NullaryUInt64ViewStaticAlignmentV1, UInt64StateBindingRelV1, data,
    Examples.VerifiedVaultPF.Proof.subjectDataV1,
    storage, reservesBinding, statusMethod, markerRegion, reservesRegion,
    statusIR]

private theorem statusStorageRel :
    InitializedUInt64StorageRelV1 data storage reservesBinding logicalTen
      #[tenBytes, tenBytes] tenBytes observedStorage := by
  refine ⟨reservesBinding_rel, rfl, logicalTen_decoded, rfl, ?_, ?_⟩
  · simp [observedStorage, storage, layoutMarkerKey]
  · simp [observedStorage, reservesBinding, reservesKey, layoutMarkerKey]

private theorem statusTargetExecution :
    executeReadOnlyMethodV1 statusIR ByteArray.empty observedStorage =
      .returned (some tenBytes) :=
  executeReadOnlyMethodV1_of_nullaryUInt64ViewStaticAlignment data storage
    reservesBinding "status" statusMethod markerRegion reservesRegion statusIR
    logicalTen #[tenBytes, tenBytes] tenBytes observedStorage statusAlignment
    statusStorageRel tenBytes_size

private theorem statusTypedWATExecution :
    executeReadOnlyWATV1 1 statusTypedWAT ByteArray.empty observedStorage =
      .returned (some tenBytes) :=
  executeReadOnlyWATV1_of_nullaryUInt64ViewStaticAlignment data storage
    reservesBinding "status" statusMethod markerRegion reservesRegion statusIR
    canonicalRegisters statusMemory logicalTen #[tenBytes, tenBytes] tenBytes
    observedStorage statusAlignment statusStorageRel tenBytes_size

example : UInt64StateBindingRelV1 data storage reservesBinding :=
  reservesBinding_rel

example :
    InitializedUInt64StorageRelV1 data storage reservesBinding logicalTen
      #[tenBytes, tenBytes] tenBytes observedStorage := by
  exact statusStorageRel

example :
    observeReadOnlyMethodV1 statusIR ByteArray.empty observedStorage =
      successfulObservation := by
  unfold observeReadOnlyMethodV1
  rw [statusTargetExecution]
  rfl

example :
    lowerReadOnlyWATOperationsV1 canonicalRegisters statusMemory
      statusIR.operations = some statusTypedWAT :=
  statusTypedWATLowering

example :
    validateReadOnlyWATMethodV1 #[markerRegion, reservesRegion] statusMemory 1
      statusTypedWAT = .ok () := by
  exact validateReadOnlyWATMethodV1_nullaryUInt64View
    #[markerRegion, reservesRegion] canonicalRegisters statusMemory markerRegion
      reservesRegion storage.markerValue
        (by simp [readOnlyWATKeyRegionEqV1])
        (by simp [readOnlyWATKeyRegionEqV1]) (by decide)

example :
    validateReadOnlyWATMethodV1 #[] statusMemory 1
      #[.localSet 1 (.i64Const 0)] = .error .localOutOfBounds := by
  rfl

example :
    validateReadOnlyWATMethodV1 #[] statusMemory 1
      #[.localSet 0 (.localGet 1)] = .error .localOutOfBounds := by
  rfl

example :
    validateReadOnlyWATMethodV1 #[markerRegion, reservesRegion] statusMemory 1
      #[.trapIfI64Ne
        (.storageRead { key := "unbound", offset := 0, length := 7 }
          canonicalRegisters.storage)
        (.i64Const 1)] = .error .keyRegionNotBound := by
  simp [validateReadOnlyWATMethodV1, validateReadOnlyWATInstructionsListV1,
    validateReadOnlyWATInstructionV1, validateReadOnlyWATI64ExprV1,
    readOnlyWATKeyRegionEqV1, markerRegion, reservesRegion, reservesKey,
    layoutMarkerKey, Bind.bind, Except.bind]

example :
    validateReadOnlyWATMethodV1 #[] { statusMemory with minPages := 0 } 1
      #[.i64Store 0 (.i64Const 0)] =
        .error .memoryOutOfBounds := by
  rfl

example :
    validateReadOnlyWATMethodV1 #[] statusMemory 1
      #[.valueReturn 4 statusMemory.valueOffset] =
        .error .unsupportedReturnWidth := by
  rfl

example :
    validateReadOnlyWATMethodV1 #[] statusMemory 1
      #[.trapIfI64Ne (.i64Const UInt64.size) (.i64Const 0)] =
        .error .i64ConstantOutOfRange := by
  rfl

example :
    executeReadOnlyWATV1 1 statusTypedWAT ByteArray.empty observedStorage =
      .returned (some tenBytes) :=
  statusTypedWATExecution

example :
    observeReadOnlyWATV1 "status" 1 statusTypedWAT ByteArray.empty
      observedStorage = successfulObservation := by
  unfold observeReadOnlyWATV1
  rw [statusTypedWATExecution]
  rfl

example :
    executeReadOnlyWATV1 1 statusTypedWAT (encodeU64le 1) observedStorage =
      .trapped .trap := by
  rfl

example :
    executeReadOnlyWATV1 1 statusTypedWAT ByteArray.empty markerOnlyStorage =
      .trapped .trap := by
  rfl

example :
    executeReadOnlyWATV1 0
      #[.readRegister canonicalRegisters.storage statusMemory.valueOffset]
      ByteArray.empty observedStorage = .trapped .registerMissing := by
  rfl

example :
    executeReadOnlyMethodV1 statusIR (encodeU64le 1) observedStorage =
      .trapped .inputLengthMismatch := by
  rfl

example (machine : ReadOnlyMethodMachineV1) :
    stepReadOnlyMethodOperationV1 machine (.assert 0) =
      .error .unsupportedOperation := by
  rfl

example :
    ¬ UInt64StateBindingRelV1 data storage
      { reservesBinding with physicalFieldIndex := 1 } := by
  simp [UInt64StateBindingRelV1, data, storage, reservesBinding]

example :
    UInt64StateBindingRelV1 nonCoincidentData nonCoincidentStorage
      nonCoincidentBinding := by
  refine ⟨?_, ?_, ?_, ?_⟩ <;> rfl

example :
    ¬ UInt64StateBindingRelV1 nonCoincidentData semanticSourcedStorage
      nonCoincidentBinding := by
  simp [UInt64StateBindingRelV1, nonCoincidentData, semanticSourcedStorage,
    nonCoincidentStorage, nonCoincidentFields, nonCoincidentBinding, data]

example :
    ¬ InitializedUInt64StorageRelV1 data storage reservesBinding logicalTen
      #[tenBytes, tenBytes] (encodeU64le 11) observedStorage := by
  intro h
  rcases h with ⟨_, _, _, _, _, hvalue⟩
  have hbytes : tenBytes = encodeU64le 11 := by
    simpa [observedStorage, storage, reservesBinding, reservesKey,
      layoutMarkerKey] using Option.some.inj hvalue
  have hnats := congrArg leBytesToNatV1 hbytes
  simp [tenBytes, leBytesToNatV1_encodeU64le] at hnats

example :
    NullaryUInt64ViewInputRelV1 3
      { callableId := 3, args := #[], context := #[] }
      statusMethod successfulObservation := by
  simp [NullaryUInt64ViewInputRelV1, statusMethod, successfulObservation]

example :
    ¬ NullaryUInt64ViewInputRelV1 3
      {
        callableId := 3
        args := #[{ typeId := 0, valueBytes := tenBytes }]
        context := #[]
      }
      statusMethod successfulObservation := by
  simp [NullaryUInt64ViewInputRelV1]

example :
    UInt64ReturnedObservationRelV1 data 0 logicalTen
      (.returned logicalTen (some { typeId := 0, valueBytes := tenBytes }) #[])
      tenBytes successfulObservation := by
  refine ⟨tenBytes_canonical, tenBytes_size, rfl, rfl, rfl, rfl, rfl, rfl⟩

example
    (admitted : AdmittedReferenceSliceV1)
    (post : LogicalStateV1)
    (responses : ExternalResponsesV1)
    (vault : ReferenceVaultSeedV1)
    (context : Array ContextInputV1)
    (value : Option ReferenceValueV1)
    (effects : Array OrderedEffectV1)
    (hadmittedData : admitted.data = data)
    (hgate :
      gateInvocation admitted logicalTen {
        callableId := 3
        args := #[]
        context := #[]
      } = .ready statusCallable #[tenBytes, tenBytes] context false)
    (hstep :
      stepReferenceSliceV1 admitted logicalTen {
        callableId := 3
        args := #[]
        context := #[]
      } responses vault = .returned post value effects) :
    post = logicalTen := by
  apply stepReferenceSliceV1_ready_viewLoad_returned_post_eq_pre
    admitted logicalTen post {
      callableId := 3
      args := #[]
      context := #[]
    } data #[tenBytes, tenBytes] tenBytes 0 0 "reserves" 3
      (some "status") context responses vault value effects hadmittedData
  · rfl
  · rfl
  · rfl
  · simpa [statusCallable] using hgate
  · exact hstep

example
    (vault : ReferenceVaultSeedV1) :
    ∃ admitted : AdmittedReferenceSliceV1,
      admitReferenceProgramSliceV1 subjectProgram = .ok admitted ∧
        NullaryUInt64ViewStaticAlignmentV1 data storage reservesBinding "status"
          statusMethod markerRegion reservesRegion statusIR ∧
        InitializedUInt64StorageRelV1 data storage reservesBinding logicalTen
          #[tenBytes, tenBytes] tenBytes successfulObservation.preStorage ∧
        NullaryUInt64ViewInputRelV1 3 {
          callableId := 3
          args := #[]
          context := #[]
        } statusMethod successfulObservation ∧
        UInt64ReturnedObservationRelV1 data 0 logicalTen
          (stepReferenceSliceV1 admitted logicalTen {
            callableId := 3
            args := #[]
            context := #[]
          } #[] vault)
          tenBytes successfulObservation := by
  obtain ⟨admitted, hadmit, hadmittedData, hgate⟩ :=
    verifiedVaultStatusReady
  refine ⟨admitted, hadmit, ?_, ?_, ?_, ?_⟩
  · simp [NullaryUInt64ViewStaticAlignmentV1, UInt64StateBindingRelV1, data,
      Examples.VerifiedVaultPF.Proof.subjectDataV1,
      storage, reservesBinding, statusMethod, markerRegion, reservesRegion,
      statusIR]
  · refine ⟨reservesBinding_rel, rfl, logicalTen_decoded, rfl, ?_, ?_⟩
    · simp [successfulObservation, observedStorage, storage, layoutMarkerKey]
    · simp [successfulObservation, observedStorage, reservesBinding, reservesKey,
        layoutMarkerKey]
  · simp [NullaryUInt64ViewInputRelV1, statusMethod, successfulObservation]
  · exact
      uint64ReturnedObservationRelV1_of_readyViewLoad admitted logicalTen {
          callableId := 3
          args := #[]
          context := #[]
        } data #[tenBytes, tenBytes] tenBytes 0 0 "reserves" 3
          (some "status") #[] vault successfulObservation hadmittedData
          (by rfl) (by rfl) (by rfl)
          (by simpa [statusCallable] using hgate)
          (by rfl) (by rfl) (by rfl) (by rfl) (by rfl)

example
    (vault : ReferenceVaultSeedV1) :
    ∃ admitted : AdmittedReferenceSliceV1,
      admitReferenceProgramSliceV1 subjectProgram = .ok admitted ∧
        UInt64ReturnedObservationRelV1 data 0 logicalTen
          (stepReferenceSliceV1 admitted logicalTen {
            callableId := 3
            args := #[]
            context := #[]
          } #[] vault)
          tenBytes
          (observeReadOnlyMethodV1 statusIR ByteArray.empty observedStorage) := by
  obtain ⟨admitted, hadmit, hadmittedData, hgate⟩ :=
    verifiedVaultStatusReady
  refine ⟨admitted, hadmit, ?_⟩
  exact
    uint64ReturnedObservationRelV1_of_readyViewLoad_and_methodExecution
      admitted logicalTen {
        callableId := 3
        args := #[]
        context := #[]
      } data #[tenBytes, tenBytes] tenBytes 0 0 "reserves" 3 "status" #[]
      vault storage reservesBinding statusMethod markerRegion reservesRegion
      statusIR observedStorage (by rfl) (by rfl) (by rfl) hadmittedData
      (by rfl) (by rfl) (by rfl)
      (by simpa [statusCallable] using hgate) statusAlignment statusStorageRel

example
    (vault : ReferenceVaultSeedV1) :
    ∃ admitted : AdmittedReferenceSliceV1,
      admitReferenceProgramSliceV1 subjectProgram = .ok admitted ∧
        UInt64ReturnedObservationRelV1 data 0 logicalTen
          (stepReferenceSliceV1 admitted logicalTen {
            callableId := 3
            args := #[]
            context := #[]
          } #[] vault)
          tenBytes
          (observeReadOnlyWATV1 "status" 1 statusTypedWAT ByteArray.empty
            observedStorage) := by
  obtain ⟨admitted, hadmit, hadmittedData, hgate⟩ :=
    verifiedVaultStatusReady
  refine ⟨admitted, hadmit, ?_⟩
  exact
    uint64ReturnedObservationRelV1_of_readyViewLoad_and_WATExecution
      admitted logicalTen {
        callableId := 3
        args := #[]
        context := #[]
      } data #[tenBytes, tenBytes] tenBytes 0 0 "reserves" 3 "status" #[]
      vault storage reservesBinding statusMethod markerRegion reservesRegion
      statusIR canonicalRegisters statusMemory observedStorage (by rfl) (by rfl)
      (by rfl) hadmittedData (by rfl) (by rfl) (by rfl)
      (by simpa [statusCallable] using hgate) statusAlignment statusStorageRel

example
    (vault : ReferenceVaultSeedV1) :
    ∃ admitted : AdmittedReferenceSliceV1,
      admitReferenceProgramSliceV1 subjectProgram = .ok admitted ∧
        ¬ UInt64ReturnedObservationRelV1 data 0 logicalTen
          (stepReferenceSliceV1 admitted logicalTen {
            callableId := 3
            args := #[]
            context := #[]
          } #[] vault)
          tenBytes wrongReturnObservation := by
  obtain ⟨admitted, hadmit, _, _⟩ := verifiedVaultStatusReady
  refine ⟨admitted, hadmit, ?_⟩
  intro hrelation
  rcases hrelation with ⟨_, _, _, _, hreturn, _, _, _⟩
  have hbytes : encodeU64le 11 = tenBytes :=
    Option.some.inj (by simpa [wrongReturnObservation] using hreturn)
  have hnats := congrArg leBytesToNatV1 hbytes
  simp [tenBytes, leBytesToNatV1_encodeU64le] at hnats

example :
    ¬ UInt64ReturnedObservationRelV1 data 0 logicalTen
      (.returned logicalTen (some { typeId := 0, valueBytes := tenBytes }) #[])
      tenBytes { successfulObservation with failureObserved := true } := by
  simp [UInt64ReturnedObservationRelV1, successfulObservation]

example :
    ¬ UInt64ReturnedObservationRelV1 data 0 logicalTen
      (.returned logicalTen (some { typeId := 0, valueBytes := tenBytes }) #[])
      tenBytes { successfulObservation with logs := #["unexpected".toUTF8] } := by
  simp [UInt64ReturnedObservationRelV1, successfulObservation]

example :
    ¬ UInt64ReturnedObservationRelV1 data 0 logicalTen
      (.returned logicalTen (some { typeId := 0, valueBytes := tenBytes }) #[])
      tenBytes { successfulObservation with promises := #["p0".toUTF8] } := by
  simp [UInt64ReturnedObservationRelV1, successfulObservation]

example :
    FailureNoCommitObservationRelV1 logicalTen
      (.reverted (.standard .assertionFailed) logicalTen)
      failedObservation := by
  simp [FailureNoCommitObservationRelV1, failedObservation]

example :
    ¬ FailureNoCommitObservationRelV1 logicalTen
      (.reverted (.standard .assertionFailed) logicalTen)
      { failedObservation with postStorage := {
          lookup := fun _ => none
        } } := by
  intro h
  rcases h with ⟨_, _, _, _, _, hstorage⟩
  have hkey := congrArg (fun snapshot => snapshot.lookup reservesKey) hstorage
  simp [failedObservation, observedStorage, reservesKey, layoutMarkerKey] at hkey

/-! Selected VerifiedVault `init()` target-refinement fixtures. -/

example :
    NullaryZeroTwoUInt64InitializerStaticAlignmentV1 data storage reservesBinding
      sharesBinding "init" initMethod markerRegion reservesRegion sharesRegion
        initIR :=
  initAlignment

example :
    lowerMethodWATOperationsV1 canonicalRegisters statusMemory
      initIR.operations = some initTypedWAT :=
  initTypedWATLowering

example :
    validateMethodWATV1 #[markerRegion, reservesRegion, sharesRegion]
      statusMemory 2 initTypedWAT = .ok () := by
  exact validateReadOnlyWATMethodV1_nullaryZeroTwoUInt64Initializer
    #[markerRegion, reservesRegion, sharesRegion] canonicalRegisters statusMemory
      markerRegion reservesRegion sharesRegion storage.markerValue
      (by simp [readOnlyWATKeyRegionEqV1])
      (by simp [readOnlyWATKeyRegionEqV1])
      (by simp [readOnlyWATKeyRegionEqV1])
      (by decide) (by decide)

example :
    executeMethodV1 initIR ByteArray.empty 0 0 emptyStorage =
      .returned none initializedZeroStorage := by
  apply executeMethodV1_of_nullaryZeroTwoUInt64InitializerStaticAlignment data
    storage reservesBinding sharesBinding "init" initMethod markerRegion
      reservesRegion sharesRegion initIR emptyStorage initAlignment
  all_goals simp [emptyStorage, markerRegion, reservesRegion, sharesRegion,
    reservesKey, sharesKey, layoutMarkerKey]

example :
    executeMethodV1 initIR ByteArray.empty 0 0 emptyStorage =
        .returned none initializedZeroStorage ∧
      InitializedZeroTwoUInt64StorageRelV1 data storage reservesBinding
        sharesBinding logicalZero initializedZeroStorage := by
  apply initializedZeroTwoUInt64StorageRelV1_of_postEncode_and_methodExecution
    data storage reservesBinding sharesBinding "init" initMethod markerRegion
      reservesRegion sharesRegion initIR emptyStorage logicalZero initAlignment
        logicalZero_encoded
  all_goals simp [emptyStorage, markerRegion, reservesRegion, sharesRegion,
    reservesKey, sharesKey, layoutMarkerKey]

/-- The join consumes an actual returned Reference-machine initializer step.
    Its logical encoding premise comes from the generic Reference theorem, not
    from the hand-authored `logicalZero` fixture above. -/
example
    (admitted : AdmittedReferenceSliceV1)
    (pre post : LogicalStateV1)
    (invocation : InvocationV1)
    (before0 before1 : ByteArray)
    (context : Array ContextInputV1)
    (responses : ExternalResponsesV1)
    (vault : ReferenceVaultSeedV1)
    (value : Option ReferenceValueV1)
    (effects : Array OrderedEffectV1)
    (hadmit : admitReferenceProgramSliceV1 subjectProgram = .ok admitted)
    (hgate :
      gateInvocation admitted pre invocation =
        .ready (initializerStoreZeroTwoCallableV1 0 0 1)
          #[before0, before1] context true)
    (hstep :
      stepReferenceSliceV1 admitted pre invocation responses vault =
        .returned post value effects) :
    executeMethodV1 initIR ByteArray.empty 0 0 emptyStorage =
        .returned none initializedZeroStorage ∧
      InitializedZeroTwoUInt64StorageRelV1 data storage reservesBinding
        sharesBinding post initializedZeroStorage := by
  have hadmittedData : admitted.data = data :=
    (admitReferenceProgramSliceV1_ok_implies subjectProgram data admitted
      Examples.VerifiedVaultPF.Proof.subjectValidationOkV1 hadmit).2
  have hpostEncode :
      encodeLogicalStateValuesV1 data true
        #[encodeU64le 0, encodeU64le 0] = .ok post := by
    apply postEncode_of_readyInitializerStoreZeroTwoV1 admitted pre post
      invocation data before0 before1 0 1 "reserves" "shares" 0 context
      responses vault value effects hadmittedData
    · rfl
    · rfl
    · rfl
    · rfl
    · rfl
    · exact hgate
    · exact hstep
  apply initializedZeroTwoUInt64StorageRelV1_of_postEncode_and_methodExecution
    data storage reservesBinding sharesBinding "init" initMethod markerRegion
      reservesRegion sharesRegion initIR emptyStorage post initAlignment
        hpostEncode
  all_goals simp [emptyStorage, markerRegion, reservesRegion, sharesRegion,
    reservesKey, sharesKey, layoutMarkerKey]

example :
    executeMethodWATV1 2 initTypedWAT ByteArray.empty 0 0 emptyStorage =
      .returned none initializedZeroStorage := by
  exact executeMethodWATV1_nullaryZeroTwoUInt64Initializer canonicalRegisters
    statusMemory markerRegion reservesRegion sharesRegion storage.markerValue
      emptyStorage
      (by simp [emptyStorage])
      (by simp [emptyStorage])
      (by simp [emptyStorage])
      (by simp [markerRegion, reservesRegion, sharesRegion, reservesKey,
        sharesKey])
      (by simp [markerRegion, reservesRegion, reservesKey, layoutMarkerKey])
      (by simp [markerRegion, sharesRegion, sharesKey, layoutMarkerKey])

example :
    executeMethodV1 initIR ⟨#[1]⟩ 0 0 emptyStorage =
      .trapped .inputLengthMismatch := by
  exact executeMethodV1_nullaryZeroTwoUInt64Initializer_nonempty_input "init"
    markerRegion reservesRegion sharesRegion storage.markerValue ⟨#[1]⟩
      emptyStorage (by decide)

example :
    executeMethodWATV1 2 initTypedWAT ⟨#[1]⟩ 0 0 emptyStorage =
      .trapped .trap := by
  exact executeMethodWATV1_nullaryZeroTwoUInt64Initializer_nonempty_input
    canonicalRegisters statusMemory markerRegion reservesRegion sharesRegion
      storage.markerValue ⟨#[1]⟩ emptyStorage (by decide)

example : initializedZeroStorage.lookup layoutMarkerKey =
    some (encodeU64le storage.markerValue) := by
  exact zeroTwoUInt64InitializerPostStorageV1_lookup_marker emptyStorage
    markerRegion reservesRegion sharesRegion storage.markerValue

example : initializedZeroStorage.lookup reservesKey = some (encodeU64le 0) := by
  exact zeroTwoUInt64InitializerPostStorageV1_lookup_field0 emptyStorage
    markerRegion reservesRegion sharesRegion storage.markerValue
      (by simp [reservesRegion, sharesRegion, reservesKey, sharesKey])
      (by simp [markerRegion, reservesRegion, reservesKey, layoutMarkerKey])

example : initializedZeroStorage.lookup sharesKey = some (encodeU64le 0) := by
  exact zeroTwoUInt64InitializerPostStorageV1_lookup_field1 emptyStorage
    markerRegion reservesRegion sharesRegion storage.markerValue
      (by simp [markerRegion, sharesRegion, sharesKey, layoutMarkerKey])

example :
    executeMethodV1 initIR ByteArray.empty 0 0 markerOnlyStorage =
      .trapped .storageAlreadyPresent := by
  exact executeMethodV1_nullaryZeroTwoUInt64Initializer_double_init "init"
    markerRegion reservesRegion sharesRegion storage.markerValue
      (encodeU64le storage.markerValue) markerOnlyStorage
      (by simp [markerOnlyStorage, markerRegion, storage])

example :
    executeMethodWATV1 2 initTypedWAT ByteArray.empty 0 0 markerOnlyStorage =
      .trapped .trap := by
  exact executeMethodWATV1_nullaryZeroTwoUInt64Initializer_double_init
    canonicalRegisters statusMemory markerRegion reservesRegion sharesRegion
      storage.markerValue (encodeU64le storage.markerValue) markerOnlyStorage
      (by simp [markerOnlyStorage, markerRegion, storage])

example :
    executeMethodV1 initIR ByteArray.empty 1 0 emptyStorage =
      .trapped .attachedDepositNotZero := by
  exact executeMethodV1_nullaryZeroTwoUInt64Initializer_nonzero_deposit "init"
    markerRegion reservesRegion sharesRegion storage.markerValue 1 emptyStorage
      (by decide)

example :
    executeMethodWATV1 2 initTypedWAT ByteArray.empty 1 0 emptyStorage =
      .trapped .trap := by
  exact executeMethodWATV1_nullaryZeroTwoUInt64Initializer_nonzero_deposit
    canonicalRegisters statusMemory markerRegion reservesRegion sharesRegion
      storage.markerValue 1 emptyStorage (by decide)

example :
    executeMethodV1 initIR ByteArray.empty 0 1 emptyStorage =
      .trapped .attachedDepositNotZero := by
  exact executeMethodV1_nullaryZeroTwoUInt64Initializer_nonzero_deposit_high
    "init" markerRegion reservesRegion sharesRegion storage.markerValue 1
      emptyStorage (by decide)

example :
    executeMethodWATV1 2 initTypedWAT ByteArray.empty 0 1 emptyStorage =
      .trapped .trap := by
  exact
    executeMethodWATV1_nullaryZeroTwoUInt64Initializer_nonzero_deposit_high
      canonicalRegisters statusMemory markerRegion reservesRegion sharesRegion
        storage.markerValue 1 emptyStorage (by decide)

example :
    ¬ NullaryZeroTwoUInt64InitializerStaticAlignmentV1 data storage
      reservesBinding sharesBinding "init" initMethod markerRegion
        reservesRegion sharesRegion
        { initIR with operations := initIR.operations.eraseIdx 4 } := by
  intro halignment
  have hir := halignment.methodIRExact
  simp [initIR] at hir

example :
    NullaryUInt64ViewStaticAlignmentV1 data storage reservesBinding "status"
      statusMethod markerRegion reservesRegion statusIR := by
  exact statusAlignment

example :
    recognizeNullaryUInt64ViewMethodV1 statusMethod =
      some statusMethodShape := by
  rfl

example :
    recognizeNullaryUInt64ViewMethodIRV1 statusIR =
      some statusMethodIRShape := by
  rfl

example :
    statusMethod = {
      name := "status"
      params := #[]
      exactInputLen := 0
      mode := .view
      depositPolicy := .queryOnly
      resultKind := .uint64
      body := #[.returnValue (.stateLoad 0)]
    } :=
  recognizeNullaryUInt64ViewMethodV1_sound statusMethod statusMethodShape rfl

example :
    statusIR = {
      name := "status"
      params := #[]
      mode := .view
      tempCount := 1
      operations := #[
        .checkInputLen 0,
        .requireLayout markerRegion storage.markerValue,
        .loadState 0 reservesRegion,
        .setReturnData 8 0
      ]
    } :=
  recognizeNullaryUInt64ViewMethodIRV1_sound statusIR statusMethodIRShape rfl

example :
    recognizeNullaryUInt64ViewMethodV1 {
      statusMethod with
      body := #[.returnValue (.stateLoad 2)]
    } = some {
      viewName := "status"
      physicalFieldIndex := 2
    } := by
  rfl

private def forgedStatusIR : MethodIR := {
  statusIR with
  operations := statusIR.operations.push (.assert 0)
}

example : recognizeNullaryUInt64ViewMethodIRV1 forgedStatusIR = none := by
  rfl

example :
    lowerReadOnlyWATOperationsV1 canonicalRegisters statusMemory
      forgedStatusIR.operations = none := by
  rfl

example :
    ¬ NullaryUInt64ViewStaticAlignmentV1 data storage reservesBinding "status"
      statusMethod markerRegion reservesRegion forgedStatusIR := by
  simp [NullaryUInt64ViewStaticAlignmentV1, forgedStatusIR, statusIR]

/-- Compile-time theorem fixtures above are the test; `run` registers the file
    in aggregate/sharded target suites without introducing a second evaluator. -/
def run : IO Unit := do
  unless emptyInvocationContextAcceptedV1 data statusCallable do
    throw <| IO.userError
      "VerifiedVault.status production context gate rejected empty context"
  IO.println "near-static-alignment-v1: ok"

end Tests.Materialization.NearStaticAlignmentV1
