/-
  ProofForgeV2.Source.ContextCommitSurfaceV1 — closed engineering surface
  recognizers for ContextRead / Commit without new AST wire tags.

  Source spellings (parser already accepts both forms):
    * ContextRead sole key: place chain `context.unixTimeSeconds`
      → Semantic `Op.ContextRead proof-forge.context.unix-time-seconds.v1`
      → result type anonymous UInt64
    * Commit: bare local-call shape `commit(expr)` when no user `fn commit`
      → Semantic `Op.Commit` (label-only identity; TypeId/valueBytes preserved)

  Deferred keys (caller/authorizers/randomness) are not recognized and stay
  fail closed. Escaped identifiers never match (exact raw spelling only).
-/
import ProofForgeV2.Source.AstSpineV1
import ProofForgeV2.Source.NameComponentV1

namespace ProofForgeV2.Source.ContextCommitSurfaceV1

open ProofForgeV2.Source.AstSpineV1
open ProofForgeV2.Source.NameComponentV1

/-- Exact unescaped raw name equality (NFC-validated component payload). -/
private def exactRaw (n : SourceNameComponentV1) (expected : String) : Bool :=
  n.raw == expected

/-- True when `place` is the sole admitted ContextRead surface
    `context.unixTimeSeconds` (field of bare name root). -/
def isContextUnixTimeSecondsPlaceV1 : PlaceV1 → Bool
  | .field (.name root) field =>
      exactRaw root "context" && exactRaw field "unixTimeSeconds"
  | _ => false

/-- True when a bare local-call callee spelling is the intrinsic Commit operator.
    Callers must still ensure no user `fn commit` shadows the intrinsic. -/
def isCommitCalleeNameV1 (callee : SourceNameComponentV1) : Bool :=
  exactRaw callee "commit"

/-- True when `expr` is the intrinsic Commit surface `commit(arg)` (one arg).
    Does not inspect declaration tables — combine with fn-shadow checks. -/
def isCommitLocalCallShapeV1 : ExprV1 → Bool
  | .localCall callee args =>
      isCommitCalleeNameV1 callee && args.size == 1
  | _ => false

/-- Sole admitted ContextRead source spelling for diagnostics. -/
def contextUnixTimeSecondsSpellingV1 : String := "context.unixTimeSeconds"

/-- Sole admitted Commit source spelling for diagnostics. -/
def commitSpellingV1 : String := "commit(_)"

end ProofForgeV2.Source.ContextCommitSurfaceV1
