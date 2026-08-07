import ProofForgeV2

namespace Examples

open ProofForgeV2.Language

-- MiniAmm formalization track — **L0 proof surface only** (ADR-0027 / RESEARCH-023).
--
-- This program is intentionally NOT the vault-internal AMM body
-- (`Examples/MiniAmm.lean`). The product simple-closure certifier admits only:
--
--   view <name>() : Bool do return true
--   invariant <name> : true
--   proof … + theorem exact <Program>.Proof.generated…V1
--
-- so a full MiniAmm carrier cannot mint the premise-free helper today.
--
-- Honest claim when `check` reports proofStatus=certified:
--   * the inline gate accepted an ordinary same-file theorem for ordinal-0
--     InvariantTheoremV1 on this simple-closure carrier;
--   * NOT that constant-product / LP safety holds on reachable states (L1);
--   * NOT target refinement / formal TASK-D2-07 / deployable with invariants
--     on EVM/Solana (materializer still fail-closed on nonempty invariants).
--
-- Business AMM: Examples/MiniAmm.lean
-- L1 sketch: ProofForgeV2.Semantic.MiniAmmSafetySketchV1
-- Ladder: docs/research/23-miniamm-formalization-ladder.md
program MiniAmmProofSurface where
  -- Nullary public Bool view required by the simple-closure family.
  view alive() : Bool do
    return true

  -- Neutral L0 name: does not claim AMM business safety.
  invariant l0Surface : true
  proof l0Surface using MiniAmmProofSurfaceProof.l0Surface

-- Author theorem: exact the elaborator-minted premise-free helper.
theorem MiniAmmProofSurfaceProof.l0Surface :
    MiniAmmProofSurface.Proof.l0Surface := by
  exact MiniAmmProofSurface.Proof.generatedL0SurfaceV1

end Examples
