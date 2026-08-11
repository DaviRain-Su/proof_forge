import Examples.VerifiedVaultPF
import ProofForgeV2.Targets.Near.StaticAlignmentV1

namespace Tests.Materialization.NearStaticAlignmentV1

open ProofForgeV2.Semantic.InvariantABI
open ProofForgeV2.Semantic.ReferenceV1
open ProofForgeV2.Semantic.WireV1
open ProofForgeV2.Targets.Near

private def data : SemanticProgramDataV1 :=
  Examples.VerifiedVaultPF.Proof.subjectDataV1

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

private def observedStorage : StorageObservationV1 := {
  lookup := fun key =>
    if key == layoutMarkerKey then some (encodeU64le storage.markerValue)
    else if key == reservesKey then some tenBytes
    else if key == sharesKey then some tenBytes
    else none
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

example : UInt64StateBindingRelV1 data storage reservesBinding :=
  reservesBinding_rel

example :
    InitializedUInt64StorageRelV1 data storage reservesBinding logicalTen
      #[tenBytes, tenBytes] tenBytes observedStorage := by
  refine ⟨reservesBinding_rel, rfl, logicalTen_decoded, rfl, ?_, ?_⟩
  · simp [observedStorage, storage, layoutMarkerKey]
  · simp [observedStorage, reservesBinding, reservesKey, layoutMarkerKey]

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

example :
    NullaryUInt64ViewStaticAlignmentV1 data storage reservesBinding "status"
      statusMethod markerRegion reservesRegion statusIR := by
  simp [NullaryUInt64ViewStaticAlignmentV1, UInt64StateBindingRelV1, data,
    Examples.VerifiedVaultPF.Proof.subjectDataV1,
    storage, reservesBinding, statusMethod, markerRegion, reservesRegion,
    statusIR]

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
  operations := statusIR.operations.push (.storeState reservesRegion 0)
}

example : recognizeNullaryUInt64ViewMethodIRV1 forgedStatusIR = none := by
  rfl

example :
    ¬ NullaryUInt64ViewStaticAlignmentV1 data storage reservesBinding "status"
      statusMethod markerRegion reservesRegion forgedStatusIR := by
  simp [NullaryUInt64ViewStaticAlignmentV1, forgedStatusIR, statusIR]

/-- Compile-time theorem fixtures above are the test; `run` registers the file
    in aggregate/sharded target suites without introducing a second evaluator. -/
def run : IO Unit :=
  IO.println "near-static-alignment-v1: ok"

end Tests.Materialization.NearStaticAlignmentV1
