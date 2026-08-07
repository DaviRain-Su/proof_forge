import ProofForgeV2

namespace Examples

open ProofForgeV2.Language

-- Platform L0 proof surface sample (ADR-0027 / RESEARCH-023).
--
-- Generic product simple-closure family (any program name may use this shape):
--
--   view <name>() : Bool do return true
--   invariant <name> : true
--   proof … + theorem exact <Program>.Proof.generated…V1
--
-- MiniAmm-specific only in the *example name*; the certifier path is platform-wide.
-- Full business MiniAmm (`Examples/MiniAmm.lean`) stays deployable without
-- nonempty invariants (materializer FC on those for EVM/Solana).
--
-- Honest claim when `check` reports proofStatus=certified:
--   * inline gate accepted ordinal-0 InvariantTheoremV1 on this simple-closure carrier;
--   * NOT AMM business safety (L1) / target refine / formal TASK-D2-07.
--
-- L1 MiniAmm instance sketch: ProofForgeV2.Semantic.MiniAmmSafetySketchV1
-- Ladder (generic stack + instances): docs/research/23-miniamm-formalization-ladder.md
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
