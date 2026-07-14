import ProofForge.Frontend.Authored.Canonicalize
import ProofForge.Frontend.Surface.Syntax

/-! Temporary canonicalization facade for compiler-internal Surface fixtures. -/

namespace ProofForge.Frontend.Surface

abbrev SurfaceNormalizeError :=
  ProofForge.Frontend.Authored.Canonicalize.AuthoredNormalizeError

def normalizeSurface (contract : SurfaceContract) :
    Except SurfaceNormalizeError ProofForge.IR.Canonical.CanonicalBundle :=
  ProofForge.Frontend.Authored.Canonicalize.normalizeAuthored contract

end ProofForge.Frontend.Surface
