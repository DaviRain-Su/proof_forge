import ProofForge.Backend.Aleo.IR
import ProofForge.IR.Examples.Counter
import ProofForge.Target.Registry

/-! Aleo/Leo codegen + registry smoke (Phase 4 ZK lane, Road 1 sourcegen).

This is the Lean-side gate for the `aleo-leo` registry target. It checks:

1. `aleo-leo` is a registered target profile (in `Target.Registry.all` /
   `knownIds`), so `proof-forge --list-targets` exposes it.
2. The full portable Counter fails closed because Leo 4.0.2 cannot return a
   mapping-derived getter value.
3. Its executable write-only fragment emits mapping-backed `initialize` and
   `increment` functions with `Final` blocks.

The heavier end-to-end gate (`leo build` + `leo test` + artifact metadata)
lives in `scripts/aleo/counter-smoke.sh` and the GitHub CI `aleo-smoke` job;
this Lean gate is the in-repo codegen witness that runs in `just check`
without needing the external `leo` CLI. -/

namespace ProofForge.Tests.AleoLeoCodegenSmoke

open ProofForge.Backend.Aleo.IR
open ProofForge.Target
open ProofForge.IR.Examples.Counter

theorem aleo_leo_in_registry : Target.all.any (fun p => p.id == "aleo-leo") = true := by
  native_decide

theorem aleo_leo_in_known_ids : Target.knownIds.contains "aleo-leo" = true := by
  native_decide

/-- Full Counter does not silently rewrite `get() -> U64` to `Final`. -/
def counterGetterFailsClosed : Bool :=
  match renderModule module with
  | .error e => e.message.contains "get" && e.message.contains "non-Unit return"
  | .ok _ => false

theorem counter_getter_fails_closed : counterGetterFailsClosed = true := by
  native_decide

def counterWriteModule : ProofForge.IR.Module :=
  { module with entrypoints := #[initializeEntrypoint, increment] }

/-- The executable state-writing fragment contains honest Leo markers. -/
def counterWriteLeoHasMarkers : Bool :=
  match renderModule counterWriteModule with
  | .ok s =>
      s.contains "program counter.aleo" &&
      s.contains "mapping count" &&
      s.contains "@noupgrade" &&
      s.contains "constructor" &&
      s.contains "fn initialize" &&
      s.contains "fn increment" &&
      !s.contains "fn get" &&
      s.contains "(n + 1u64)" &&
      s.contains "Final"
  | .error _ => false

theorem counter_write_leo_has_markers : counterWriteLeoHasMarkers = true := by
  native_decide

example : True := by
  have _ := @aleo_leo_in_registry
  have _ := @aleo_leo_in_known_ids
  have _ := @counter_getter_fails_closed
  have _ := @counter_write_leo_has_markers
  exact True.intro

end ProofForge.Tests.AleoLeoCodegenSmoke

def main : IO UInt32 := do
  IO.println "aleo-leo-codegen-smoke: full Counter getter rejected; executable write fragment checked"
  return 0
