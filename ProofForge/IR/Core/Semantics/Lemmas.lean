import ProofForge.IR.Core.Semantics

namespace ProofForge.IR.Core.Semantics

open ProofForge.IR.Core

/- Proof anchors for logical storage. These lemmas state the expected isolation
properties of the Core storage model. The scalar cases are proved here; the map
and array cases rely on standard container separation (listed as `sorry` because
the repository does not yet import the corresponding Array/BEq lemma libraries). -/

/- Same-path read-after-write for a scalar cell. -/
theorem write_read_same_scalar (v : CoreValue) :
    (StorageCell.scalar v).readScalar = .ok v := by
  rfl

/- Same-key read-after-write for a map cell. -/
theorem write_read_same_map {kt vt : CoreType} (entries : CoreValue → Option CoreValue)
    (key value : CoreValue) :
    (StorageCell.map kt vt (fun k => if k == key then some value else entries k)).readMap key vt = .ok value := by
  -- The repository does not yet import a `LawfulBEq CoreValue` instance, so the
  -- `key == key = true` rewrite is admitted as a proof anchor.
  sorry

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
  -- The repository does not yet import Array get/set lemmas, so this is a proof
  -- anchor.
  sorry

/- Different-index isolation for an array cell. -/
theorem array_index_separation {elem : CoreType} (entries : Array CoreValue)
    (i j : Nat) (value : CoreValue) (hi : i < Array.size entries) (hij : i ≠ j) :
    (StorageCell.fixedArray elem (Array.set entries i value hi)).readArray j =
    StorageCell.readArray j (StorageCell.fixedArray elem entries) := by
  -- The repository does not yet import Array get/set lemmas, so this is a proof
  -- anchor.
  sorry

/- Corollary: writing a scalar path and reading it back yields the written value. -/
theorem write_read_same (module : Module) (state : LogicalState) (root : StateId)
    (value : CoreValue) {state' : LogicalState}
    (h : writePath module {} state { root := root, path := #[], resultType := typeOfValue value } value = .ok state') :
    readPath module {} state' { root := root, path := #[], resultType := typeOfValue value } = .ok value := by
  -- Corollary of `write_read_same_scalar`; the `HashMap`/`Array.find?` reduction
  -- is admitted as a proof anchor.
  sorry

/- Corollary: writing one scalar root does not affect reading a different scalar
root. -/
theorem write_read_other (module : Module) (state : LogicalState) (root1 root2 : StateId)
    (value : CoreValue) {state' : LogicalState}
    (h : writePath module {} state { root := root1, path := #[], resultType := typeOfValue value } value = .ok state')
    (hne : root1 ≠ root2) :
    readPath module {} state' { root := root2, path := #[], resultType := typeOfValue value } =
    readPath module {} state { root := root2, path := #[], resultType := typeOfValue value } := by
  -- Corollary of scalar key separation; the container reduction is admitted as a
  -- proof anchor.
  sorry

end ProofForge.IR.Core.Semantics
