/-
  ProofForgeV2.Source.ContextCommitSurfaceV1 — closed engineering surface
  recognizers for ContextRead / Commit without new AST wire tags.

  Source spellings (parser already accepts place chains):
    * ContextRead time: place chain `context.unixTimeSeconds`
      → Semantic `Op.ContextRead proof-forge.context.unix-time-seconds.v1`
      → result type anonymous UInt64
    * ContextRead caller (N-2): place chain `context.caller`
      → Semantic `Op.ContextRead proof-forge.context.caller.v1`
      → result type anonymous Principal
    * ContextRead block height (ADR-0031 S2): place chain `context.blockHeight`
      → Semantic `Op.ContextRead proof-forge.context.block-height.v1`
      → result type anonymous UInt64
    * Commit: bare local-call shape `commit(expr)` when no user `fn commit`
      → Semantic `Op.Commit` (label-only identity; TypeId/valueBytes preserved)

  Deferred keys (authorizers/randomness) are not recognized and stay fail
  closed. Escaped identifiers never match (exact raw spelling only).
-/
import ProofForgeV2.Source.AstSpineV1
import ProofForgeV2.Source.NameComponentV1

namespace ProofForgeV2.Source.ContextCommitSurfaceV1

open ProofForgeV2.Source.AstSpineV1
open ProofForgeV2.Source.NameComponentV1

/-- Exact unescaped raw name equality (NFC-validated component payload). -/
private def exactRaw (n : SourceNameComponentV1) (expected : String) : Bool :=
  n.raw == expected

/-- True when `place` is the ContextRead surface `context.unixTimeSeconds`. -/
def isContextUnixTimeSecondsPlaceV1 : PlaceV1 → Bool
  | .field (.name root) field =>
      exactRaw root "context" && exactRaw field "unixTimeSeconds"
  | _ => false

/-- True when `place` is the ContextRead surface `context.caller` (N-2). -/
def isContextCallerPlaceV1 : PlaceV1 → Bool
  | .field (.name root) field =>
      exactRaw root "context" && exactRaw field "caller"
  | _ => false

/-- True when `place` is the ContextRead surface `context.blockHeight`
    (ADR-0031 S2). -/
def isContextBlockHeightPlaceV1 : PlaceV1 → Bool
  | .field (.name root) field =>
      exactRaw root "context" && exactRaw field "blockHeight"
  | _ => false

/-- True when `place` is any admitted ContextRead surface. -/
def isContextReadPlaceV1 (p : PlaceV1) : Bool :=
  isContextUnixTimeSecondsPlaceV1 p || isContextCallerPlaceV1 p ||
    isContextBlockHeightPlaceV1 p

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

/-- Admitted ContextRead source spellings for diagnostics. -/
def contextUnixTimeSecondsSpellingV1 : String := "context.unixTimeSeconds"

def contextCallerSpellingV1 : String := "context.caller"

/-- Admitted ContextRead block-height source spelling for diagnostics
    (ADR-0031 S2). -/
def contextBlockHeightSpellingV1 : String := "context.blockHeight"

/-- Sole admitted Commit source spelling for diagnostics. -/
def commitSpellingV1 : String := "commit(_)"

end ProofForgeV2.Source.ContextCommitSurfaceV1
