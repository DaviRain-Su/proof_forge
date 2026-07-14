import ProofForge.IR.Core.Semantics

namespace ProofForge.IR.Core.Semantics

open ProofForge.IR.Core

local instance {ε α : Type} [BEq ε] [BEq α] : BEq (Except ε α) where
  beq
    | .ok lhs, .ok rhs => lhs == rhs
    | .error lhs, .error rhs => lhs == rhs
    | .ok _, .error _ | .error _, .ok _ => false

theorem write_read_same_scalar (previous value : CoreValue)
    (htype : (typeOfValue value == typeOfValue previous) = true) :
    match (StorageCell.scalar previous).writeScalar value with
    | .ok updated => updated.readScalar = .ok value
    | .error _ => False := by
  simp [StorageCell.writeScalar, StorageCell.readScalar, htype]

theorem write_read_same_array {elem : CoreType} (entries : Array CoreValue)
    (index : Nat) (value : CoreValue)
    (htype : (typeOfValue value == elem) = true) (hindex : index < entries.size) :
    match (StorageCell.fixedArray elem entries).writeArray index value with
    | .ok updated => updated.readArray index = .ok value
    | .error _ => False := by
  have htypeNe : (typeOfValue value != elem) = false := by
    simp only [bne, htype, Bool.not_true]
  simp [StorageCell.writeArray, StorageCell.readArray, htypeNe, hindex]

theorem array_index_separation_cell {elem : CoreType} (entries : Array CoreValue)
    (writtenIndex readIndex : Nat) (value : CoreValue)
    (htype : (typeOfValue value == elem) = true)
    (hwrite : writtenIndex < entries.size) (hne : writtenIndex ≠ readIndex) :
    match (StorageCell.fixedArray elem entries).writeArray writtenIndex value with
    | .ok updated => updated.readArray readIndex =
        (StorageCell.fixedArray elem entries).readArray readIndex
    | .error _ => False := by
  have htypeNe : (typeOfValue value != elem) = false := by
    simp only [bne, htype, Bool.not_true]
  simp only [StorageCell.writeArray, htypeNe, Bool.false_eq_true, ↓reduceIte,
    hwrite, StorageCell.readArray]
  by_cases hread : readIndex < entries.size
  · simp [hread, hne]
  · simp [hread]

theorem map_key_separation_cell :
    (((StorageCell.map .u64 .u64 none #[]).writeMap (.u64 1) (.u64 100)).bind
      (fun updated => updated.readMap (.u64 2) .u64) ==
      (StorageCell.map .u64 .u64 none #[]).readMap (.u64 2) .u64) = true := by
  native_decide

theorem findMapValueList_upsert_other
    (entries : List (CoreValue × CoreValue)) (writeKey readKey value : CoreValue)
    (hkeys : writeKey ≠ readKey)
    (hbeq : ∀ lhs rhs : CoreValue, (lhs == rhs) = true ↔ lhs = rhs) :
    findMapValueList? (upsertMapEntryList entries writeKey value) readKey =
      findMapValueList? entries readKey := by
  induction entries with
  | nil =>
      simp [upsertMapEntryList, findMapValueList?, hbeq, hkeys]
  | cons entry rest ih =>
      rcases entry with ⟨key, previous⟩
      by_cases hwrite : key = writeKey
      · subst key
        simp [upsertMapEntryList, findMapValueList?, hbeq, hkeys]
      · by_cases hread : key = readKey
        · subst key
          simp [upsertMapEntryList, findMapValueList?, hbeq, hwrite, hkeys]
        · simp [upsertMapEntryList, findMapValueList?, hbeq, hwrite, hread, ih]

theorem findMapValue_upsert_other
    (entries : Array (CoreValue × CoreValue)) (writeKey readKey value : CoreValue)
    (hkeys : writeKey ≠ readKey)
    (hbeq : ∀ lhs rhs : CoreValue, (lhs == rhs) = true ↔ lhs = rhs) :
    findMapValue? (upsertMapEntry entries writeKey value) readKey =
      findMapValue? entries readKey := by
  unfold findMapValue? upsertMapEntry
  simpa using findMapValueList_upsert_other entries.toList writeKey readKey value hkeys hbeq

theorem findMapValueList_upsert_other_of_separated
    (entries : List (CoreValue × CoreValue)) (writeKey readKey value : CoreValue)
    (hkeys : (writeKey == readKey) = false)
    (hkeysReverse : (readKey == writeKey) = false)
    (hentries : ∀ entry ∈ entries,
      (entry.1 == writeKey) = false ∨ (entry.1 == readKey) = false) :
    findMapValueList? (upsertMapEntryList entries writeKey value) readKey =
      findMapValueList? entries readKey := by
  induction entries with
  | nil => simp [upsertMapEntryList, findMapValueList?, hkeys]
  | cons entry rest ih =>
      rcases entry with ⟨key, previous⟩
      have hhead := hentries (key, previous) (by simp)
      have htail : ∀ entry ∈ rest,
          (entry.1 == writeKey) = false ∨ (entry.1 == readKey) = false := by
        intro tailEntry hmem
        exact hentries tailEntry (by simp [hmem])
      cases hwrite : (key == writeKey) with
      | true =>
          have hread : (key == readKey) = false := by
            cases hhead with
            | inl h => simp_all
            | inr h => exact h
          simp [upsertMapEntryList, findMapValueList?, hwrite, hread, hkeys]
      | false =>
          cases hread : (key == readKey) with
          | true => simp [upsertMapEntryList, findMapValueList?, hwrite, hread]
          | false =>
              simpa [upsertMapEntryList, findMapValueList?, hwrite, hread] using ih htail

theorem findMapValue_upsert_other_of_separated
    (entries : Array (CoreValue × CoreValue)) (writeKey readKey value : CoreValue)
    (hkeys : (writeKey == readKey) = false)
    (hkeysReverse : (readKey == writeKey) = false)
    (hentries : ∀ entry ∈ entries.toList,
      (entry.1 == writeKey) = false ∨ (entry.1 == readKey) = false) :
    findMapValue? (upsertMapEntry entries writeKey value) readKey =
      findMapValue? entries readKey := by
  unfold findMapValue? upsertMapEntry
  simpa using findMapValueList_upsert_other_of_separated entries.toList writeKey readKey
    value hkeys hkeysReverse hentries

theorem array_set_other {α : Type} (entries : Array α) (writeIndex readIndex : Nat)
    (value : α) (hwrite : writeIndex < entries.size)
    (hread : readIndex < entries.size) (hne : writeIndex ≠ readIndex) :
    (entries.set writeIndex value hwrite)[readIndex]'(by
      simpa [Array.size_set] using hread) = entries[readIndex]'hread := by
  simp [Array.getElem_set, hne]

def scalarPathModule : Module := {
  name := "ScalarPathProof"
  state := #[⟨⟨0⟩, .scalar .u64⟩, ⟨⟨1⟩, .scalar .u64⟩]
}

def scalarPath (root : StateId) : StorageRef := {
  root := root
  path := #[]
  resultType := .u64
}

theorem scalar_path_write_read :
    ((writePath scalarPathModule {} default (scalarPath ⟨0⟩) (.u64 7)).bind
      (fun updated => readPath scalarPathModule {} updated (scalarPath ⟨0⟩)) ==
    .ok (.u64 7)) = true := by
  native_decide

theorem scalar_path_other_root :
    ((writePath scalarPathModule {} default (scalarPath ⟨0⟩) (.u64 7)).bind
      (fun updated => readPath scalarPathModule {} updated (scalarPath ⟨1⟩)) ==
    readPath scalarPathModule {} default (scalarPath ⟨1⟩)) = true := by
  native_decide

def mapPathModule : Module := {
  name := "MapPathProof"
  state := #[⟨⟨2⟩, .map .u64 .u64 (some 2)⟩]
}

def mapPath (keyId : ValueId) : StorageRef := {
  root := ⟨2⟩
  path := #[.mapKey { id := keyId, type := .u64 }]
  resultType := .u64
}

def mapPathEnv : Env := Std.HashMap.ofList [
  (⟨20⟩, .u64 1), (⟨21⟩, .u64 2)
]

theorem map_path_write_read :
    ((writePath mapPathModule mapPathEnv default (mapPath ⟨20⟩) (.u64 100)).bind
      (fun updated => readPath mapPathModule mapPathEnv updated (mapPath ⟨20⟩)) ==
    .ok (.u64 100)) = true := by
  native_decide

theorem map_path_key_separation :
    ((writePath mapPathModule mapPathEnv default (mapPath ⟨20⟩) (.u64 100)).bind
      (fun updated => readPath mapPathModule mapPathEnv updated (mapPath ⟨21⟩)) ==
    readPath mapPathModule mapPathEnv default (mapPath ⟨21⟩)) = true := by
  native_decide

def arrayPathModule : Module := {
  name := "ArrayPathProof"
  state := #[⟨⟨3⟩, .fixedArray .u64 3⟩]
}

def arrayPath (indexId : ValueId) : StorageRef := {
  root := ⟨3⟩
  path := #[.index { id := indexId, type := .u64 }]
  resultType := .u64
}

def arrayPathEnv : Env := Std.HashMap.ofList [
  (⟨30⟩, .u64 1), (⟨31⟩, .u64 2)
]

theorem array_path_write_read :
    ((writePath arrayPathModule arrayPathEnv default (arrayPath ⟨30⟩) (.u64 99)).bind
      (fun updated => readPath arrayPathModule arrayPathEnv updated (arrayPath ⟨30⟩)) ==
    .ok (.u64 99)) = true := by
  native_decide

theorem array_path_index_separation :
    ((writePath arrayPathModule arrayPathEnv default (arrayPath ⟨30⟩) (.u64 99)).bind
      (fun updated => readPath arrayPathModule arrayPathEnv updated (arrayPath ⟨31⟩)) ==
    readPath arrayPathModule arrayPathEnv default (arrayPath ⟨31⟩)) = true := by
  native_decide

theorem write_read_same_cell (cell updated : StorageCell) (value : CoreValue)
    (hwrite : cell.writeScalar value = .ok updated) :
    updated.readScalar = .ok value := by
  cases cell with
  | scalar previous =>
      simp only [StorageCell.writeScalar] at hwrite
      split at hwrite
      · cases hwrite
        rfl
      · contradiction
  | map _ _ _ _ | mapN _ _ _ _ | fixedArray _ _ | dynamicArray _ _ | record _ _ =>
      simp [StorageCell.writeScalar] at hwrite

theorem write_read_same (module : Module) (state : LogicalState)
    (root : StateId) (previous value : CoreValue) (type : CoreType)
    (hdecl : module.state.find? (·.id == root) =
      some { id := root, shape := StateShape.scalar type })
    (hcell : getStateCell module state root = .ok (.scalar previous))
    (hvalue : valueHasType module value type = true)
    (hfootprint : valueFootprint value ≤ maxLogicalCollectionLength) :
    (writePath module {} state { root := root, path := #[], resultType := type } value).bind
      (fun updated =>
        readPath module {} updated { root := root, path := #[], resultType := type }) =
      .ok value := by
  have hnot : ¬maxLogicalCollectionLength < valueFootprint value :=
    Nat.not_lt.mpr hfootprint
  have hvalid : validateStorageCell module (StateShape.scalar type) (StorageCell.scalar value) = .ok () := by
    simp [validateStorageCell, hvalue, hnot]
    rfl
  have hwrite : writePath module {} state
      { root := root, path := #[], resultType := type } value =
      .ok (setStateCell state root (.scalar value)) := by
    unfold writePath
    rw [hvalue]
    simp only [↓reduceIte]
    rw [hcell]
    simp only [writeNestedValue, Bind.bind, Except.bind]
    rw [hdecl]
    change (validateStorageCell module (StateShape.scalar type) (StorageCell.scalar value)).bind
      (fun _ => .ok (setStateCell state root (.scalar value))) =
      .ok (setStateCell state root (.scalar value))
    rw [hvalid]
    rfl
  have hget : getStateCell module (setStateCell state root (.scalar value)) root =
      .ok (.scalar value) := by
    unfold getStateCell
    rw [hdecl]
    simp [setStateCell]
    change (validateStorageCell module (StateShape.scalar type) (StorageCell.scalar value)).bind
      (fun _ => .ok (StorageCell.scalar value)) = .ok (StorageCell.scalar value)
    rw [hvalid]
    rfl
  rw [hwrite]
  change readPath module {} (setStateCell state root (.scalar value))
    { root := root, path := #[], resultType := type } = .ok value
  unfold readPath
  rw [hget]
  change (readNestedValue module {} value []).bind
    (fun result => if valueHasType module result type then .ok result else .error .typeMismatch) =
    .ok value
  simp only [readNestedValue]
  change (Except.ok value : Except RuntimeError CoreValue).bind
    (fun result => if valueHasType module result type then .ok result else .error .typeMismatch) =
    .ok value
  change (if valueHasType module value type then (.ok value : Except RuntimeError CoreValue)
    else .error .typeMismatch) = .ok value
  simp [hvalue]

theorem write_read_other (module : Module) (env : Env) (state : LogicalState)
    (writeRef readRef : StorageRef) (value : CoreValue) (cell : StorageCell)
    (hvalues : readRef.root.value ≠ writeRef.root.value)
    (hwrite : writePath module env state writeRef value =
      .ok (setStateCell state writeRef.root cell)) :
    (writePath module env state writeRef value).bind
      (fun updated => readPath module env updated readRef) =
    readPath module env state readRef := by
  rw [hwrite]
  change readPath module env (setStateCell state writeRef.root cell) readRef =
    readPath module env state readRef
  have hget :
      getStateCell module (setStateCell state writeRef.root cell) readRef.root =
      getStateCell module state readRef.root := by
    unfold getStateCell
    simp [setStateCell, hvalues]
  unfold readPath
  rw [hget]

private def readMapSingle (module : Module) (env : Env) (valueType : CoreType)
    (entries : Array (CoreValue × CoreValue)) (keyRef : ValueRef) :
    Except RuntimeError CoreValue := do
  let key ← evalRef env keyRef
  let value := (findMapValue? entries key).getD (typeDefaultForModule module valueType)
  let result ← readNestedValue module env value []
  if valueHasType module result valueType then .ok result else .error .typeMismatch

private theorem readPath_map_single (module : Module) (env : Env)
    (state : LogicalState) (root : StateId) (keyType valueType : CoreType)
    (capacity : Option Nat) (entries : Array (CoreValue × CoreValue))
    (keyRef : ValueRef)
    (hcell : getStateCell module state root =
      .ok (.map keyType valueType capacity entries)) :
    readPath module env state {
      root := root, path := #[.mapKey keyRef], resultType := valueType
    } = readMapSingle module env valueType entries keyRef := by
  unfold readPath
  rw [hcell]
  rfl

private def readArraySingle (module : Module) (env : Env) (element : CoreType)
    (entries : Array CoreValue) (indexRef : ValueRef) : Except RuntimeError CoreValue := do
  let result ← readNestedValue module env (.fixedArray element entries) [.index indexRef]
  if valueHasType module result element then .ok result else .error .typeMismatch

private theorem readPath_array_single (module : Module) (env : Env)
    (state : LogicalState) (root : StateId) (element : CoreType)
    (entries : Array CoreValue) (indexRef : ValueRef)
    (hcell : getStateCell module state root = .ok (.fixedArray element entries)) :
    readPath module env state {
      root := root, path := #[.index indexRef], resultType := element
    } = readArraySingle module env element entries indexRef := by
  unfold readPath
  rw [hcell]
  rfl

theorem map_key_separation_of_lookup (module : Module) (env : Env)
    (state updated : LogicalState) (root : StateId)
    (keyType valueType : CoreType) (capacity : Option Nat)
    (entries updatedEntries : Array (CoreValue × CoreValue))
    (writeKeyRef readKeyRef : ValueRef) (writeKey readKey value : CoreValue)
    (_hkeys : (readKey == writeKey) = false)
    (_hwriteEval : evalRef env writeKeyRef = .ok writeKey)
    (hreadEval : evalRef env readKeyRef = .ok readKey)
    (hwrite : writePath module env state {
      root := root, path := #[.mapKey writeKeyRef], resultType := valueType
    } value = .ok updated)
    (hbefore : getStateCell module state root =
      .ok (.map keyType valueType capacity entries))
    (hafter : getStateCell module updated root =
      .ok (.map keyType valueType capacity updatedEntries))
    (hlookup : findMapValue? updatedEntries readKey = findMapValue? entries readKey) :
    (writePath module env state {
      root := root, path := #[.mapKey writeKeyRef], resultType := valueType
    } value).bind (fun state' => readPath module env state' {
      root := root, path := #[.mapKey readKeyRef], resultType := valueType
    }) = readPath module env state {
      root := root, path := #[.mapKey readKeyRef], resultType := valueType
  } := by
  rw [hwrite]
  change readPath module env updated {
    root := root, path := #[.mapKey readKeyRef], resultType := valueType
  } = readPath module env state {
    root := root, path := #[.mapKey readKeyRef], resultType := valueType
  }
  rw [readPath_map_single module env updated root keyType valueType capacity
    updatedEntries readKeyRef hafter]
  rw [readPath_map_single module env state root keyType valueType capacity
    entries readKeyRef hbefore]
  unfold readMapSingle
  rw [hreadEval]
  change (if valueHasType module
      ((findMapValue? updatedEntries readKey).getD (typeDefaultForModule module valueType))
      valueType then
      (Except.ok ((findMapValue? updatedEntries readKey).getD
        (typeDefaultForModule module valueType)) : Except RuntimeError CoreValue)
    else Except.error .typeMismatch) =
    (if valueHasType module
      ((findMapValue? entries readKey).getD (typeDefaultForModule module valueType))
      valueType then
      (Except.ok ((findMapValue? entries readKey).getD
        (typeDefaultForModule module valueType)) : Except RuntimeError CoreValue)
    else Except.error .typeMismatch)
  rw [hlookup]

theorem array_index_separation_of_lookup (module : Module) (env : Env)
    (state updated : LogicalState) (root : StateId) (element : CoreType)
    (entries updatedEntries : Array CoreValue)
    (writeIndexRef readIndexRef : ValueRef) (writeIndex readIndex : Nat)
    (writeIndexValue readIndexValue value : CoreValue)
    (hreadBound : readIndex < entries.size)
    (hupdatedBound : readIndex < updatedEntries.size)
    (_hindices : writeIndex ≠ readIndex)
    (_hwriteEval : evalRef env writeIndexRef = .ok writeIndexValue)
    (_hwriteIndex : asArrayIndex writeIndexValue = .ok writeIndex)
    (hreadEval : evalRef env readIndexRef = .ok readIndexValue)
    (hreadIndex : asArrayIndex readIndexValue = .ok readIndex)
    (hwrite : writePath module env state {
      root := root, path := #[.index writeIndexRef], resultType := element
    } value = .ok updated)
    (hbefore : getStateCell module state root = .ok (.fixedArray element entries))
    (hafter : getStateCell module updated root = .ok (.fixedArray element updatedEntries))
    (hlookup : updatedEntries[readIndex] = entries[readIndex]) :
    (writePath module env state {
      root := root, path := #[.index writeIndexRef], resultType := element
    } value).bind (fun state' => readPath module env state' {
      root := root, path := #[.index readIndexRef], resultType := element
    }) = readPath module env state {
      root := root, path := #[.index readIndexRef], resultType := element
    } := by
  rw [hwrite]
  change readPath module env updated {
    root := root, path := #[.index readIndexRef], resultType := element
  } = readPath module env state {
    root := root, path := #[.index readIndexRef], resultType := element
  }
  rw [readPath_array_single module env updated root element updatedEntries
    readIndexRef hafter]
  rw [readPath_array_single module env state root element entries readIndexRef hbefore]
  unfold readArraySingle readNestedValue
  rw [hreadEval]
  simp only [Bind.bind, Except.bind, readNestedValue]
  rw [hreadIndex]
  simp only [Bind.bind, Except.bind]
  rw [dif_pos hupdatedBound, dif_pos hreadBound, hlookup]

theorem map_key_separation (module : Module) (env : Env)
    (state updated : LogicalState) (root : StateId)
    (keyType valueType : CoreType) (capacity : Option Nat)
    (entries : Array (CoreValue × CoreValue))
    (writeKeyRef readKeyRef : ValueRef) (writeKey readKey value : CoreValue)
    (hkeys : (writeKey == readKey) = false)
    (hkeysReverse : (readKey == writeKey) = false)
    (hentries : ∀ entry ∈ entries.toList,
      (entry.1 == writeKey) = false ∨ (entry.1 == readKey) = false)
    (hwriteEval : evalRef env writeKeyRef = .ok writeKey)
    (hreadEval : evalRef env readKeyRef = .ok readKey)
    (hwrite : writePath module env state {
      root := root, path := #[.mapKey writeKeyRef], resultType := valueType
    } value = .ok updated)
    (hbefore : getStateCell module state root =
      .ok (.map keyType valueType capacity entries))
    (hafter : getStateCell module updated root =
      .ok (.map keyType valueType capacity (upsertMapEntry entries writeKey value))) :
    (writePath module env state {
      root := root, path := #[.mapKey writeKeyRef], resultType := valueType
    } value).bind (fun state' => readPath module env state' {
      root := root, path := #[.mapKey readKeyRef], resultType := valueType
    }) = readPath module env state {
      root := root, path := #[.mapKey readKeyRef], resultType := valueType
    } := by
  have hlookup := findMapValue_upsert_other_of_separated entries writeKey readKey value
    hkeys hkeysReverse hentries
  exact map_key_separation_of_lookup module env state updated root keyType valueType
    capacity entries (upsertMapEntry entries writeKey value) writeKeyRef readKeyRef
    writeKey readKey value hkeysReverse hwriteEval hreadEval hwrite hbefore hafter hlookup

theorem array_index_separation (module : Module) (env : Env)
    (state updated : LogicalState) (root : StateId) (element : CoreType)
    (entries : Array CoreValue) (writeIndexRef readIndexRef : ValueRef)
    (writeIndex readIndex : Nat) (writeIndexValue readIndexValue value : CoreValue)
    (hwriteBound : writeIndex < entries.size) (hreadBound : readIndex < entries.size)
    (hindices : writeIndex ≠ readIndex)
    (hwriteEval : evalRef env writeIndexRef = .ok writeIndexValue)
    (hwriteIndex : asArrayIndex writeIndexValue = .ok writeIndex)
    (hreadEval : evalRef env readIndexRef = .ok readIndexValue)
    (hreadIndex : asArrayIndex readIndexValue = .ok readIndex)
    (hwrite : writePath module env state {
      root := root, path := #[.index writeIndexRef], resultType := element
    } value = .ok updated)
    (hbefore : getStateCell module state root = .ok (.fixedArray element entries))
    (hafter : getStateCell module updated root =
      .ok (.fixedArray element (entries.set writeIndex value hwriteBound))) :
    (writePath module env state {
      root := root, path := #[.index writeIndexRef], resultType := element
    } value).bind (fun state' => readPath module env state' {
      root := root, path := #[.index readIndexRef], resultType := element
    }) = readPath module env state {
      root := root, path := #[.index readIndexRef], resultType := element
    } := by
  have hupdatedBound : readIndex < (entries.set writeIndex value hwriteBound).size := by
    simpa [Array.size_set] using hreadBound
  have hlookup :
      (entries.set writeIndex value hwriteBound)[readIndex]'hupdatedBound =
      entries[readIndex]'hreadBound :=
    array_set_other entries writeIndex readIndex value hwriteBound hreadBound hindices
  exact array_index_separation_of_lookup module env state updated root element entries
    (entries.set writeIndex value hwriteBound) writeIndexRef readIndexRef writeIndex
    readIndex writeIndexValue readIndexValue value hreadBound hupdatedBound hindices
    hwriteEval hwriteIndex hreadEval hreadIndex hwrite hbefore hafter hlookup

theorem write_read_other_concrete :
    ((writePath scalarPathModule {} default (scalarPath ⟨0⟩) (.u64 7)).bind
      (fun updated => readPath scalarPathModule {} updated (scalarPath ⟨1⟩)) ==
    readPath scalarPathModule {} default (scalarPath ⟨1⟩)) = true :=
  scalar_path_other_root

theorem write_read_same_concrete :
    ((writePath scalarPathModule {} default (scalarPath ⟨0⟩) (.u64 7)).bind
      (fun updated => readPath scalarPathModule {} updated (scalarPath ⟨0⟩)) ==
    .ok (.u64 7)) = true :=
  scalar_path_write_read

theorem map_key_separation_concrete :
    ((writePath mapPathModule mapPathEnv default (mapPath ⟨20⟩) (.u64 100)).bind
      (fun updated => readPath mapPathModule mapPathEnv updated (mapPath ⟨21⟩)) ==
    readPath mapPathModule mapPathEnv default (mapPath ⟨21⟩)) = true :=
  map_path_key_separation

theorem array_index_separation_concrete :
    ((writePath arrayPathModule arrayPathEnv default (arrayPath ⟨30⟩) (.u64 99)).bind
      (fun updated => readPath arrayPathModule arrayPathEnv updated (arrayPath ⟨31⟩)) ==
    readPath arrayPathModule arrayPathEnv default (arrayPath ⟨31⟩)) = true :=
  array_path_index_separation

end ProofForge.IR.Core.Semantics
