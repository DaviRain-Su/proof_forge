import ProofForge.Backend.Aleo.IR
import ProofForge.IR.Contract

/-! Aleo/Leo generic lowering regression: map storage.

Companion to `Tests/AleoLeoCodegenSmoke.lean` (which covers the scalar Counter
fixture). This smoke exercises the **generic** stateful lowering on a module
that uses **map** storage (`state ledger: map U64 => U64`), proving the
post-spike lowering handles more than the three hardcoded Counter entrypoints:

- a scalar→mapping rewrite is NOT used (this is a real Leo `mapping K => V`);
- `storageMapSet` lowers to `Mapping::set`;
- `storageMapGet` lowers to `Mapping::get_or_use`;
- stateful entrypoints wrap their bodies in `return final { … };` returning
  `Final`, exactly like the Counter fixture.

It is a Lean-side gate (no external `leo` CLI needed). -/

namespace ProofForge.Tests.AleoLeoMapLoweringSmoke

open ProofForge.IR
open ProofForge.Backend.Aleo.IR

/-- `state ledger: map U64(8) => U64` — a public Leo `mapping u64 => u64`. -/
def ledgerState : StateDecl :=
  { id := "ledger", kind := .map .u64 8, type := .u64 }

/-- `fn seed() -> Final { return final { Mapping::set(ledger, 0u64, 42u64); }; }` -/
def seed : Entrypoint :=
  { name := "seed"
    body := #[ .effect (.storageMapSet "ledger" (.literal (.u64 0)) (.literal (.u64 42))) ] }

/-- `fn bump() -> Final { return final {
       let v: u64 = Mapping::get_or_use(ledger, 0u64, 0u64);
       Mapping::set(ledger, 0u64, (v + 1u64));
    }; }` -/
def bump : Entrypoint :=
  { name := "bump"
    body := #[
      .letBind "v" .u64 (.effect (.storageMapGet "ledger" (.literal (.u64 0)))),
      .effect (.storageMapSet "ledger" (.literal (.u64 0)) (.add (.local "v") (.literal (.u64 1))))
    ] }

def ledgerModule : Module :=
  { name := "Ledger", state := #[ledgerState], entrypoints := #[seed, bump] }

/-- The ledger fixture lowers to a Leo program without error. -/
def ledgerLowersOk : Bool :=
  match renderModule ledgerModule with
  | .ok _ => true
  | .error _ => false

theorem ledger_lowers_ok : ledgerLowersOk = true := by
  native_decide

/-- The lowered Leo source contains the generic map-storage markers. -/
def ledgerLeoHasMarkers : Bool :=
  match renderModule ledgerModule with
  | .ok s =>
      s.contains "program ledger.aleo" &&
      s.contains "mapping ledger: u64 => u64" &&
      s.contains "Mapping::set" &&
      s.contains "Mapping::get_or_use" &&
      s.contains "fn seed" &&
      s.contains "fn bump" &&
      s.contains "Final"
  | .error _ => false

theorem ledger_leo_has_markers : ledgerLeoHasMarkers = true := by
  native_decide

example : True := by
  have _ := @ledger_lowers_ok
  have _ := @ledger_leo_has_markers
  exact True.intro

end ProofForge.Tests.AleoLeoMapLoweringSmoke

def main : IO UInt32 := do
  IO.println "aleo-leo-map-lowering-smoke: generic map-storage lowering checked"
  return 0
