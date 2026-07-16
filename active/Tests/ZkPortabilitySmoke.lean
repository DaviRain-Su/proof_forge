import ProofForge.Backend.Aleo.IR
import ProofForge.Backend.Psy.IR
import ProofForge.IR.Contract
import ProofForge.IR.Examples.Counter

/-! ZK portability: one portable module → both ZK targets.

ProofForge's thesis is portable contracts across chains. With both ZK
sourcegen targets now implemented (`psy-dpn` and `aleo-leo`), this gate lowers
the SAME executable Counter write fragment through BOTH backends and asserts:

- both lower without error;
- both expose the same entrypoint surface (`initialize`, `increment`).

This is the cross-target portability witness for the ZK lane (Psy `.psy` and
Aleo `.leo` are different surface languages, but the portable contract reaches
both). -/

namespace ProofForge.Tests.ZkPortabilitySmoke

open ProofForge.IR

def counterWriteModule : Module :=
  { Examples.Counter.module with
    entrypoints := #[Examples.Counter.initializeEntrypoint, Examples.Counter.increment] }

def psyOut := ProofForge.Backend.Psy.IR.renderModule counterWriteModule
def aleoOut := ProofForge.Backend.Aleo.IR.renderModule counterWriteModule

/-- Counter lowers on BOTH ZK sourcegen targets. -/
def bothLower : Bool :=
  match psyOut, aleoOut with
  | .ok _, .ok _ => true
  | _, _ => false

theorem both_lower : bothLower = true := by native_decide

/-- Both targets expose the same entrypoint surface. -/
def sameSurface : Bool :=
  match psyOut, aleoOut with
  | .ok p, .ok a =>
      ["initialize", "increment"].all (fun n => p.contains n && a.contains n) &&
      !a.contains "fn get"
  | _, _ => false

theorem same_surface : sameSurface = true := by native_decide

example : True := by
  have _ := @both_lower
  have _ := @same_surface
  exact True.intro

end ProofForge.Tests.ZkPortabilitySmoke

def main : IO UInt32 := do
  IO.println "zk-portability-smoke: executable Counter write fragment lowers on both ZK targets"
  return 0
