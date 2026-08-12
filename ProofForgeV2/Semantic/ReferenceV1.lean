import ProofForgeV2.Semantic.InvariantABI
import ProofForgeV2.Semantic.ReferenceMachineV1

/-
  ProofForgeV2.Semantic.ReferenceV1 — public reference-semantics façade.

  Runtime carriers, admission, and the engineering reference machine are
  defined by ReferenceMachineV1 under this same public namespace. The lower
  machine depends only on InvariantFoundationV1, preserving an acyclic path for
  the later InvariantABI-owned formal evaluator.

  Engineering SPEC-SEM-001-shaped `step` façade (this module):
    * validates/admits via `admitReferenceProgramSliceV1` first
    * wire OR unsupported admission failure → `.trapped .invalidCore pre`
    * success → sole machine authority `stepReferenceSliceV1` (default vault)
    * NOT formal TASK-D2-07 / TST-SEM-002/003 completion

  N5b engineering slice (not formal TASK-D2-07 / TST-SEM-002/003):
    * `Op.ContextRead` sole catalog key `proof-forge.context.unix-time-seconds.v1`
      (UInt64) is stepped from the immutable per-invocation `InvocationV1.context`
      snapshot (strict-ascending exact key/type/canonical gate; missing/extra/
      wrong type → `invalidInvocation` before lifecycle/responses).
    * `Op.Commit` is label-only identity: result = operand exact TypeId +
      canonical valueBytes; no hash/salt/re-encode; does not publish overlay or
      effects by itself. Only `.returned` commits overlay/effects (existing
      terminal rule). Revert/trap discard provisional overlay; ContextRead and
      Commit leave no residual side effect after rollback.
    * N5 Normalize product surface (`context.unixTimeSeconds`, bare `commit(x)`)
      is executed through the same admitted machine; pureFn ContextRead/Commit
      remain Normalize fail-closed (init/entry/view only).
-/

namespace ProofForgeV2.Semantic.ReferenceV1

open ProofForgeV2.Semantic.InvariantABI
open ProofForgeV2.Semantic.WireV1

/-- Engineering SPEC-SEM-001-shaped public `step` façade.

    Thin packaging over the admitted-slice machine only:
      1. `admitReferenceProgramSliceV1 p`
      2. `.error` (wire OR unsupported) → `.trapped .invalidCore pre`
      3. `.ok admitted` → `stepReferenceSliceV1` with default vault seed

    Sole machine authority remains `stepReferenceSliceV1`. This is **not**
    formal TASK-D2-07 / TST-SEM-002/003 completion. -/
def step
    (p : SemanticProgramV1)
    (pre : LogicalStateV1)
    (invocation : InvocationV1)
    (responses : ExternalResponsesV1) : OutcomeV1 :=
  match admitReferenceProgramSliceV1 p with
  | .error _ => .trapped .invalidCore pre
  | .ok admitted => stepReferenceSliceV1 admitted pre invocation responses

/-- When admission succeeds, the public façade is definitionally the admitted
    machine step (default vault). -/
theorem step_eq_stepReferenceSliceV1_of_admit
    (p : SemanticProgramV1)
    (pre : LogicalStateV1)
    (invocation : InvocationV1)
    (responses : ExternalResponsesV1)
    (admitted : AdmittedReferenceSliceV1)
    (hadmit : admitReferenceProgramSliceV1 p = .ok admitted) :
    step p pre invocation responses =
      stepReferenceSliceV1 admitted pre invocation responses := by
  simp only [step, hadmit]

/-- Admission failure (wire or unsupported) maps to SPEC invalidCore with the
    exact supplied pre-state; responses are ignored. -/
theorem step_trapped_invalidCore_of_admit_error
    (p : SemanticProgramV1)
    (pre : LogicalStateV1)
    (invocation : InvocationV1)
    (responses : ExternalResponsesV1)
    (e : ReferenceAdmissionErrorV1)
    (hadmit : admitReferenceProgramSliceV1 p = .error e) :
    step p pre invocation responses = .trapped .invalidCore pre := by
  simp only [step, hadmit]

end ProofForgeV2.Semantic.ReferenceV1
