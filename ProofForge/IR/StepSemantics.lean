import ProofForge.IR.Contract
import ProofForge.IR.Semantics

namespace ProofForge.IR.StepSemantics

open ProofForge.IR.Semantics

/-! Tier C-proof Phase 6a — inductive trace predicate + soundness by induction.

This is the first universally-quantified IR-side trace layer. It defines a
generic inductive `IRTraceMatches` predicate that is structurally recursive
over the call list (induction over `List Call`), with the executable runner
`runTraceListGen` proven *sound* against it by `induction calls` (NOT
`native_decide`). The predicate is parameterized by an atomic per-call step
function so it stays EVM-agnostic; `ProofForge.Backend.Evm.Refinement`
instantiates it with `runEntrypointObservable` to recover the existing
`runTrace`/`runTraceList` semantics and bridge the `native_decide` theorems.

Design choice: big-step induction over the call list (option (b) in the
feasibility doc). We keep the existing big-step interpreter
`IR.Semantics.runEntrypointWithArgs` as the atomic step and layer the
inductive predicate on top, rather than reframing the IR semantics as a
small-step `step : State -> Option State` relation. This is the minimal
change that enables induction over the trace without refactoring the whole
IR interpreter; a small-step relation (Phase 6c prerequisite) is left to 6b+.
-/

/-- Generic list-fold runner mirroring `Refinement.runTraceList` but abstract
over the atomic per-call step. Threaded through `IR.Semantics.State`. The
atomic step returns a pair; we use a named-tuple lambda (no anonymous
pattern match) so `Except.bind` reduces by `rfl`/`simp`. -/
def runTraceListGen {Call Obs : Type} (step : State → Call → Except String (State × Obs))
    : List Call → State → Except String (State × Array Obs)
  | [], s => .ok (s, #[])
  | c :: rest, s =>
    (step s c).bind fun so =>
    (runTraceListGen step rest so.1).bind fun soso =>
    .ok (soso.1, #[so.2] ++ soso.2)

@[simp] theorem runTraceListGen_nil {Call Obs : Type}
    (step : State → Call → Except String (State × Obs)) (s : State) :
    runTraceListGen step [] s = .ok (s, #[]) := rfl

@[simp] theorem runTraceListGen_cons_ok {Call Obs : Type}
    (step : State → Call → Except String (State × Obs)) (c : Call) (rest : List Call)
    (s s' : State) (o : Obs) (sFinal : State) (os : Array Obs)
    (h1 : step s c = .ok (s', o))
    (h2 : runTraceListGen step rest s' = .ok (sFinal, os)) :
    runTraceListGen step (c :: rest) s = .ok (sFinal, #[o] ++ os) := by
  rw [runTraceListGen, h1]
  show (runTraceListGen step rest s').bind (fun soso => .ok (soso.fst, #[o] ++ soso.snd)) = _
  rw [h2]; rfl

@[simp] theorem runTraceListGen_cons_err_step {Call Obs : Type}
    (step : State → Call → Except String (State × Obs)) (c : Call) (rest : List Call)
    (s : State) (e : String) (h1 : step s c = .error e) :
    runTraceListGen step (c :: rest) s = .error e := by
  rw [runTraceListGen, h1]; rfl

@[simp] theorem runTraceListGen_cons_err_rest {Call Obs : Type}
    (step : State → Call → Except String (State × Obs)) (c : Call) (rest : List Call)
    (s s' : State) (o : Obs) (e : String)
    (h1 : step s c = .ok (s', o))
    (h2 : runTraceListGen step rest s' = .error e) :
    runTraceListGen step (c :: rest) s = .error e := by
  rw [runTraceListGen, h1]
  show (runTraceListGen step rest s').bind (fun soso => .ok (soso.fst, #[o] ++ soso.snd)) = _
  rw [h2]; rfl

/-- Inductive trace-matches predicate, structurally recursive over the call
list. `IRTraceMatches step s calls os` holds iff running `step` over `calls`
from `s` yields exactly `os`, matching `runTraceListGen step calls s`. -/
inductive IRTraceMatches {Call Obs : Type} (step : State → Call → Except String (State × Obs))
    : State → List Call → Array Obs → Prop where
  | nil : IRTraceMatches step s [] #[]
  | cons (h : step s c = .ok (s', o)) (hrest : IRTraceMatches step s' rest os) :
      IRTraceMatches step s (c :: rest) (#[o] ++ os)

/-- Soundness: the executable runner agrees with the inductive predicate for
ALL states and ALL call lists. This is the first universally-quantified lemma
in the Tier C-proof chain. Discharged by `induction calls generalizing s`
(not `native_decide`). -/
theorem runTraceListGen_sound {Call Obs : Type}
    (step : State → Call → Except String (State × Obs))
    (calls : List Call) (s : State) :
    match runTraceListGen step calls s with
    | .ok (_, os) => IRTraceMatches step s calls os
    | .error _ => True := by
  induction calls generalizing s with
  | nil =>
    show match runTraceListGen step [] s with
      | .ok (_, os) => IRTraceMatches step s [] os
      | .error _ => True
    rw [runTraceListGen_nil]
    exact IRTraceMatches.nil
  | cons c rest ih =>
    show match runTraceListGen step (c :: rest) s with
      | .ok (_, os) => IRTraceMatches step s (c :: rest) os
      | .error _ => True
    cases h1 : step s c with
    | error _ => rw [runTraceListGen_cons_err_step _ _ _ _ _ h1]; trivial
    | ok s'o =>
      obtain ⟨s', o⟩ := s'o
      cases h2 : runTraceListGen step rest s' with
      | error _ => rw [runTraceListGen_cons_err_rest _ _ _ _ _ _ _ h1 h2]; trivial
      | ok sFinalos =>
        obtain ⟨sFinal, os⟩ := sFinalos
        rw [runTraceListGen_cons_ok _ _ _ _ _ _ _ _ h1 h2]
        refine IRTraceMatches.cons h1 ?_
        have := ih s'
        rw [h2] at this
        exact this

/-- Completeness: any `IRTraceMatches` derivation is realized by the runner.
Proven by induction on the `IRTraceMatches` derivation. -/
theorem IRTraceMatches_complete {Call Obs : Type}
    (step : State → Call → Except String (State × Obs))
    {s : State} {calls : List Call} {os : Array Obs}
    (h : IRTraceMatches step s calls os) :
    ∃ s', runTraceListGen step calls s = .ok (s', os) := by
  induction h with
  | nil => exact ⟨_, rfl⟩
  | cons hstep hrest ih =>
    obtain ⟨s'', hrest'⟩ := ih
    refine ⟨s'', ?_⟩
    exact runTraceListGen_cons_ok _ _ _ _ _ _ _ _ hstep hrest'

/-- `IRTraceMatches` holds iff the runner returns the matching observable
array. Combines soundness and completeness into a usable iff. -/
theorem IRTraceMatches_iff_runTraceListGen {Call Obs : Type}
    (step : State → Call → Except String (State × Obs))
    (s : State) (calls : List Call) (os : Array Obs) :
    IRTraceMatches step s calls os ↔
      ∃ s', runTraceListGen step calls s = .ok (s', os) :=
  ⟨IRTraceMatches_complete step, fun ⟨_, h⟩ => by
    have snd := runTraceListGen_sound step calls s
    rw [h] at snd
    exact snd⟩

/-- Decidable instance via the iff bridge: compute `runTraceListGen` and
compare the observable array. This is what lets `native_decide` re-prove the
Counter/ValueVault theorems as `IRTraceMatches` instances without changing
their truth values. -/
instance irTraceMatchesDecidable {Call Obs : Type}
    (step : State → Call → Except String (State × Obs))
    [DecidableEq Obs] (s : State) (calls : List Call) (os : Array Obs) :
    Decidable (IRTraceMatches step s calls os) := by
  cases h : runTraceListGen step calls s with
  | error _ =>
    refine isFalse (fun hh => ?_)
    obtain ⟨_, hh'⟩ := IRTraceMatches_complete step hh
    rw [hh'] at h
    cases h
  | ok s'os' =>
    obtain ⟨_, os'⟩ := s'os'
    by_cases heq : os' = os
    · exact isTrue (by
        have snd := runTraceListGen_sound step calls s
        rw [h] at snd
        rw [← heq]
        exact snd)
    · refine isFalse (fun hh => ?_)
      obtain ⟨_, hh'⟩ := IRTraceMatches_complete step hh
      rw [hh'] at h
      cases h
      exact heq rfl

end ProofForge.IR.StepSemantics