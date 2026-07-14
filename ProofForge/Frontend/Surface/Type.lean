import ProofForge.Frontend.Authored.Type

/-! Temporary compatibility names for compiler-internal Surface fixtures.

The final authoring type system is owned by `Frontend.Authored`. Surface
fixtures retain these aliases only until A-CUT4 deletes the duplicate fixture
route.
-/

namespace ProofForge.Frontend.Surface

abbrev SurfaceType := ProofForge.Frontend.Authored.AuthoredType

end ProofForge.Frontend.Surface
