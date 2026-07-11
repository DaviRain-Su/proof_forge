import ProofForge.IR.Core.Semantics

namespace ProofForge.IR.Core.Semantics

open ProofForge.IR.Core

/- Proof anchors for logical storage. These lemmas state the expected isolation
properties of the Core storage model. -/

/- Same-path read-after-write for a scalar cell. -/
theorem write_read_same_scalar (v : CoreValue) :
    (StorageCell.scalar v).readScalar = .ok v := by
  rfl

/- Different-key isolation for a map cell. The hypothesis is stated as a
concrete `BEq` false equality so that it can be discharged by `simp` on concrete
values. -/
theorem map_key_separation {kt vt : CoreType} (entries : CoreValue → Option CoreValue)
    (key1 key2 value : CoreValue) (h : (key2 == key1) = false) :
    (StorageCell.map kt vt (fun k => if k == key1 then some value else entries k)).readMap key2 vt =
    .ok (entries key2 |>.getD (typeDefault vt)) := by
  simp [StorageCell.readMap, h]

/- Same-index read-after-write for an array cell. -/
theorem write_read_same_array {elem : CoreType} (entries : Array CoreValue)
    (i : Nat) (value : CoreValue) (hi : i < Array.size entries) :
    (StorageCell.fixedArray elem (Array.set entries i value hi)).readArray i = .ok value := by
  simp [StorageCell.readArray, hi]

/- Different-index isolation for an array cell. -/
theorem array_index_separation {elem : CoreType} (entries : Array CoreValue)
    (i j : Nat) (value : CoreValue) (hi : i < Array.size entries) (hij : i ≠ j) :
    (StorageCell.fixedArray elem (Array.set entries i value hi)).readArray j =
    StorageCell.readArray j (StorageCell.fixedArray elem entries) := by
  simp only [StorageCell.readArray]
  split <;> rename_i h
  · have hj : j < entries.size := by simpa using h
    simp [hj, hij]
  · have hj : ¬j < entries.size := by simpa using h
    simp [hj]

private theorem writePath_scalar_state (module : Module) (state : LogicalState)
    (root : StateId) (value : CoreValue) {state' : LogicalState}
    (h : writePath module {} state
      { root := root, path := #[], resultType := typeOfValue value } value = .ok state') :
    state' = setStateCell state root (.scalar value) := by
  simp only [writePath] at h
  generalize hc : getStateCell module state root = cellResult at h
  cases cellResult with
  | error e =>
    change Except.error e = Except.ok state' at h
    contradiction
  | ok cell =>
    cases cell with
    | scalar old =>
      by_cases hty : typeOfValue value == typeOfValue old
      · have hw : StorageCell.writeScalar value (.scalar old) =
            Except.ok (.scalar value) := by
          simp [StorageCell.writeScalar, hty]
        dsimp only [Bind.bind, Pure.pure, Except.instMonad, Except.bind] at h
        rw [hw] at h
        injection h with hs
        exact hs.symm
      · have hw : StorageCell.writeScalar value (.scalar old) =
            Except.error RuntimeError.typeMismatch := by
          simp [StorageCell.writeScalar, hty]
        dsimp only [Bind.bind, Pure.pure, Except.instMonad, Except.bind] at h
        rw [hw] at h
        contradiction
    | map _ _ _ =>
      change Except.error RuntimeError.invalidStorageShape = Except.ok state' at h
      contradiction
    | fixedArray _ _ =>
      change Except.error RuntimeError.invalidStorageShape = Except.ok state' at h
      contradiction
    | dynamicArray _ _ =>
      change Except.error RuntimeError.invalidStorageShape = Except.ok state' at h
      contradiction
    | record _ =>
      change Except.error RuntimeError.invalidStorageShape = Except.ok state' at h
      contradiction

/- Corollary: writing a scalar path and reading it back yields the written value. -/
theorem write_read_same (module : Module) (state : LogicalState) (root : StateId)
    (value : CoreValue) {state' : LogicalState}
    (h : writePath module {} state { root := root, path := #[], resultType := typeOfValue value } value = .ok state') :
    readPath module {} state' { root := root, path := #[], resultType := typeOfValue value } = .ok value := by
  have hs := writePath_scalar_state module state root value h
  subst state'
  simp only [readPath, getStateCell, setStateCell]
  dsimp only [Bind.bind, Pure.pure, Except.instMonad, Except.bind,
    StorageCell.readScalar]
  simp

/- Corollary: writing one scalar root does not affect reading a different scalar
root. -/
theorem write_read_other (module : Module) (state : LogicalState) (root1 root2 : StateId)
    (value : CoreValue) {state' : LogicalState}
    (h : writePath module {} state { root := root1, path := #[], resultType := typeOfValue value } value = .ok state')
    (hne : root1 ≠ root2) :
    readPath module {} state' { root := root2, path := #[], resultType := typeOfValue value } =
    readPath module {} state { root := root2, path := #[], resultType := typeOfValue value } := by
  have hs := writePath_scalar_state module state root1 value h
  subst state'
  have hvalues : root2.value ≠ root1.value := by
    intro hv
    apply hne
    cases root1
    cases root2
    simp_all
  simp [readPath, getStateCell, setStateCell, hvalues]

end ProofForge.IR.Core.Semantics
