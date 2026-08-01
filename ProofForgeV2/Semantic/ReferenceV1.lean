import ProofForgeV2.Semantic.InvariantABI
import ProofForgeV2.Semantic.ReferenceMachineV1

/-
  ProofForgeV2.Semantic.ReferenceV1 — public reference-semantics façade.

  Runtime carriers, admission, and the engineering reference machine are
  defined by ReferenceMachineV1 under this same public namespace. The lower
  machine depends only on InvariantFoundationV1, preserving an acyclic path for
  the later InvariantABI-owned formal evaluator.

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
