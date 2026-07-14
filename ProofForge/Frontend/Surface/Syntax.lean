import ProofForge.Frontend.Authored.Syntax
import ProofForge.Frontend.Surface.Type

/-! Temporary compatibility names for compiler-internal Surface fixtures.

No syntax is owned here. The independent frontend model lives under
`Frontend.Authored`; these aliases keep the existing fixture normalizer
buildable until A-CUT4 removes the Surface route.
-/

namespace ProofForge.Frontend.Surface

abbrev SourceSpan := ProofForge.Frontend.Authored.SourceSpan
abbrev SurfaceLiteral := ProofForge.Frontend.Authored.AuthoredLiteral
abbrev SurfaceArithOp := ProofForge.Frontend.Authored.AuthoredArithOp
abbrev SurfaceCompareOp := ProofForge.Frontend.Authored.AuthoredCompareOp
abbrev SurfaceUnaryOp := ProofForge.Frontend.Authored.AuthoredUnaryOp
abbrev SurfaceContextField := ProofForge.Frontend.Authored.AuthoredContextField
abbrev SurfaceCrosscallMode := ProofForge.Frontend.Authored.AuthoredCrosscallMode
abbrev SurfaceLValue := ProofForge.Frontend.Authored.AuthoredLValue
abbrev SurfaceExpr := ProofForge.Frontend.Authored.AuthoredExpr
abbrev SurfaceStmt := ProofForge.Frontend.Authored.AuthoredStmt
abbrev SurfaceStateKind := ProofForge.Frontend.Authored.AuthoredStateKind
abbrev SurfaceStateDecl := ProofForge.Frontend.Authored.AuthoredStateDecl
abbrev SurfaceEventField := ProofForge.Frontend.Authored.AuthoredEventField
abbrev SurfaceEventDecl := ProofForge.Frontend.Authored.AuthoredEventDecl
abbrev SurfaceEntrypointKind := ProofForge.Frontend.Authored.AuthoredEntrypointKind
abbrev SurfaceMutability := ProofForge.Frontend.Authored.AuthoredMutability
abbrev SurfaceParam := ProofForge.Frontend.Authored.AuthoredParam
abbrev SurfaceEntrypoint := ProofForge.Frontend.Authored.AuthoredEntrypoint
abbrev SurfaceStructField := ProofForge.Frontend.Authored.AuthoredStructField
abbrev SurfaceStructDecl := ProofForge.Frontend.Authored.AuthoredStructDecl
abbrev SurfaceConstructorBindingKind :=
  ProofForge.Frontend.Authored.AuthoredConstructorBindingKind
abbrev SurfaceConstructorBinding :=
  ProofForge.Frontend.Authored.AuthoredConstructorBinding
abbrev SurfaceConstructorParam :=
  ProofForge.Frontend.Authored.AuthoredConstructorParam
abbrev SurfaceErrorDecl := ProofForge.Frontend.Authored.AuthoredErrorDecl
abbrev SurfaceIntentKind := ProofForge.Frontend.Authored.AuthoredIntentKind
abbrev SurfaceIntent := ProofForge.Frontend.Authored.AuthoredIntent
abbrev SurfaceContract := ProofForge.Frontend.Authored.AuthoredContract

end ProofForge.Frontend.Surface
