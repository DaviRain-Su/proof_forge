import ProofForge.Frontend.Authored.Validate
import ProofForge.Frontend.Surface.Syntax

/-! Temporary validation facade for compiler-internal Surface fixtures. -/

namespace ProofForge.Frontend.Surface

abbrev SurfaceError := ProofForge.Frontend.Authored.AuthoredValidationError

def validateSurface (contract : SurfaceContract) : Except SurfaceError Unit :=
  ProofForge.Frontend.Authored.validateAuthored contract

end ProofForge.Frontend.Surface
