import Lean
import ProofForgeV2.Core.Diagnostic

namespace ProofForgeV2.Source.SpanV1

/-- Half-open UTF-8 byte range in the immutable source snapshot. -/
structure SourceByteSpanV1 where
  startByte : UInt64
  endByte : UInt64
  deriving BEq, DecidableEq, Repr

private def invalidSpan (detail : String) : CompileResult α :=
  .error (.invalidProgram detail)

private def validateOriginalParserTree (root : Lean.Syntax) : CompileResult Unit := do
  if root.isMissing then
    return ← invalidSpan "source span cannot be extracted from missing syntax"
  let mut pending := #[root]
  while !pending.isEmpty do
    let current := pending.back!
    pending := pending.pop
    match current with
    | .atom (.original ..) _ => pure ()
    | .ident (.original ..) .. => pure ()
    | .node .none _ children =>
        -- Optional grammar fields may contain `Syntax.missing`; they carry no
        -- boundary and are ignored unless they are the requested root.
        for child in children do
          if !child.isMissing then
            pending := pending.push child
    | _ =>
        return ← invalidSpan
          "source span requires unexpanded syntax from the original parser"

private def originalStartByte? : Lean.SourceInfo → Option Nat
  | .original _ position _ _ => some position.byteIdx
  | _ => none

private def originalEndByte? : Lean.SourceInfo → Option Nat
  | .original _ _ _ endPosition => some endPosition.byteIdx
  | _ => none

/--
Extract the half-open byte span of original parser syntax. The caller supplies
the exact immutable source snapshot length so forged or stale positions fail
closed before they can become a `SourceOrigin`.
-/
def originalSyntaxByteSpanV1
    (sourceByteLength : Nat) (sourceSyntax : Lean.Syntax) : CompileResult SourceByteSpanV1 := do
  validateOriginalParserTree sourceSyntax
  unless sourceByteLength < UInt64.size do
    return ← invalidSpan "source byte length exceeds the UInt64 span domain"
  let startByte ← match originalStartByte? sourceSyntax.getHeadInfo with
    | some value => pure value
    | none => invalidSpan "source syntax has no original start position"
  let endByte ← match originalEndByte? sourceSyntax.getTailInfo with
    | some value => pure value
    | none => invalidSpan "source syntax has no original end position"
  unless startByte < UInt64.size && endByte < UInt64.size do
    return ← invalidSpan "source syntax position exceeds the UInt64 span domain"
  unless startByte ≤ endByte do
    return ← invalidSpan "source syntax start position exceeds its end position"
  unless endByte ≤ sourceByteLength do
    return ← invalidSpan "source syntax span exceeds the immutable source snapshot"
  pure {
    startByte := UInt64.ofNat startByte
    endByte := UInt64.ofNat endByte
  }

end ProofForgeV2.Source.SpanV1
