import ProofForgeV2.Semantic.InvariantABI
import ProofForgeV2.Semantic.ReferenceMachineV1

/-
  ProofForgeV2.Semantic.ReferenceV1 — public reference-semantics façade.

  Runtime carriers, admission, and the engineering reference machine are
  defined by ReferenceMachineV1 under this same public namespace. The lower
  machine depends only on InvariantFoundationV1, preserving an acyclic path for
  the later InvariantABI-owned formal evaluator.
-/
