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

private def originalTokenRange
    (source : String) (sourceByteLength : Nat) :
    Lean.SourceInfo → CompileResult (Nat × Nat)
  | .original leading position trailing endPosition => do
      unless leading.str == source && trailing.str == source do
        return ← invalidSpan
          "source syntax does not belong to the immutable source snapshot"
      let startByte := position.byteIdx
      let endByte := endPosition.byteIdx
      let leadingStart := leading.startPos.byteIdx
      let leadingEnd := leading.stopPos.byteIdx
      let trailingStart := trailing.startPos.byteIdx
      let trailingEnd := trailing.stopPos.byteIdx
      unless startByte < UInt64.size && endByte < UInt64.size do
        return ← invalidSpan "source syntax position exceeds the UInt64 span domain"
      unless String.Pos.Raw.isValid source leading.startPos &&
          String.Pos.Raw.isValid source leading.stopPos &&
          String.Pos.Raw.isValid source position &&
          String.Pos.Raw.isValid source endPosition &&
          String.Pos.Raw.isValid source trailing.startPos &&
          String.Pos.Raw.isValid source trailing.stopPos do
        return ← invalidSpan "source syntax position is not a UTF-8 boundary"
      unless leadingStart ≤ leadingEnd && leadingEnd == startByte &&
          endByte == trailingStart && trailingStart ≤ trailingEnd do
        return ← invalidSpan "source syntax whitespace bounds are inconsistent"
      unless startByte ≤ endByte do
        return ← invalidSpan "source syntax start position exceeds its end position"
      unless trailingEnd ≤ sourceByteLength do
        return ← invalidSpan "source syntax span exceeds the immutable source snapshot"
      pure (startByte, endByte)
  | _ => invalidSpan
      "source span requires unexpanded syntax from the original parser"

private def extractOriginalParserSpan
    (source : String) (root : Lean.Syntax) : CompileResult SourceByteSpanV1 := do
  let sourceByteLength := source.toUTF8.size
  unless sourceByteLength < UInt64.size do
    return ← invalidSpan "source byte length exceeds the UInt64 span domain"
  let mut pending := #[root]
  let mut firstStart? : Option Nat := none
  let mut previousEnd? : Option Nat := none
  let mut finalEnd? : Option Nat := none
  while !pending.isEmpty do
    let current := pending.back!
    pending := pending.pop
    match current with
    | .missing =>
        return ← invalidSpan "source span cannot contain missing syntax"
    | .atom info _ =>
        let (startByte, endByte) ← originalTokenRange source sourceByteLength info
        match previousEnd? with
        | some previousEnd =>
            unless previousEnd ≤ startByte do
              return ← invalidSpan "source syntax token positions are not ordered"
        | none => firstStart? := some startByte
        previousEnd? := some endByte
        finalEnd? := some endByte
    | .ident info rawValue _ _ =>
        let (startByte, endByte) ← originalTokenRange source sourceByteLength info
        unless rawValue.str == source && rawValue.startPos.byteIdx == startByte &&
            rawValue.stopPos.byteIdx == endByte do
          return ← invalidSpan
            "source identifier does not belong to the immutable source snapshot"
        match previousEnd? with
        | some previousEnd =>
            unless previousEnd ≤ startByte do
              return ← invalidSpan "source syntax token positions are not ordered"
        | none => firstStart? := some startByte
        previousEnd? := some endByte
        finalEnd? := some endByte
    | .node .none _ children =>
        -- Push in reverse so the explicit worklist visits source order.
        for child in children.toList.reverse do
          pending := pending.push child
    | _ =>
        return ← invalidSpan
          "source span requires unexpanded syntax from the original parser"
  match firstStart?, finalEnd? with
  | some startByte, some endByte =>
      pure {
        startByte := UInt64.ofNat startByte
        endByte := UInt64.ofNat endByte
      }
  | _, _ => invalidSpan "source syntax contains no original token"

/--
Extract the half-open byte span of original parser syntax. The caller supplies
the exact immutable source snapshot so forged or stale positions fail
closed before they can become a `SourceOrigin`.
-/
def originalSyntaxByteSpanV1
    (source : String) (sourceSyntax : Lean.Syntax) : CompileResult SourceByteSpanV1 :=
  extractOriginalParserSpan source sourceSyntax

end ProofForgeV2.Source.SpanV1
