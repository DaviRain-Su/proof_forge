import ProofForgeV2.Source.SpanV1

namespace Tests.Language.SourceSpan

open ProofForgeV2
open ProofForgeV2.Source.SpanV1

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def liftSpan
    (label : String) (result : CompileResult SourceByteSpanV1) : IO SourceByteSpanV1 :=
  match result with
  | .ok span => pure span
  | .error error => throw <| IO.userError s!"{label}: unexpected error: {error.render}"

private def expectInvalid
    (label : String) (result : CompileResult SourceByteSpanV1) : IO Unit :=
  match result with
  | .error (.invalidProgram _) => pure ()
  | .error error =>
      throw <| IO.userError s!"{label}: expected invalid-program, got {error.render}"
  | .ok span => throw <| IO.userError s!"{label}: unexpectedly produced {repr span}"

private def originalAtom
    (startByte endByte : Nat) (value : String := "token") : Lean.Syntax :=
  .atom (.original "".toRawSubstring (.mk startByte)
    "".toRawSubstring (.mk endByte)) value

private def syntheticAtom
    (startByte endByte : Nat) (canonical : Bool) : Lean.Syntax :=
  .atom (.synthetic (.mk startByte) (.mk endByte) canonical) "token"

def run : IO Unit := do
  let token := originalAtom 4 9
  let span ← liftSpan "original atom" (originalSyntaxByteSpanV1 12 token)
  expect (span == { startByte := 4, endByte := 9 })
    "original token positions must become an exact half-open byte span"

  let wrapped := Lean.Syntax.node .none `ProofForgeV2.Tests.SourceSpan #[
    originalAtom 1 3 "é",
    Lean.Syntax.missing,
    originalAtom 4 5 "x"
  ]
  let wrappedSpan ← liftSpan "parser node with optional missing field"
    (originalSyntaxByteSpanV1 5 wrapped)
  expect (wrappedSpan == { startByte := 1, endByte := 5 })
    "parser nodes must use the first and last original UTF-8 byte positions"
  let multibyteSpan ← liftSpan "multibyte token"
    (originalSyntaxByteSpanV1 "é".toUTF8.size (originalAtom 0 2 "é"))
  expect (multibyteSpan == { startByte := 0, endByte := 2 })
    "source offsets must count UTF-8 bytes rather than Unicode scalar values"

  expectInvalid "missing root"
    (originalSyntaxByteSpanV1 0 Lean.Syntax.missing)
  expectInvalid "non-canonical synthetic syntax"
    (originalSyntaxByteSpanV1 12 (syntheticAtom 4 9 false))
  expectInvalid "canonical synthetic syntax"
    (originalSyntaxByteSpanV1 12 (syntheticAtom 4 9 true))
  let mixedTree := Lean.Syntax.node .none `ProofForgeV2.Tests.SourceSpan #[
    originalAtom 0 1 "a", syntheticAtom 1 2 true, originalAtom 2 3 "b"
  ]
  expectInvalid "synthetic descendant"
    (originalSyntaxByteSpanV1 3 mixedTree)
  expectInvalid "reversed source positions"
    (originalSyntaxByteSpanV1 12 (originalAtom 9 4))
  expectInvalid "position beyond source snapshot"
    (originalSyntaxByteSpanV1 8 token)
  expectInvalid "source length outside UInt64 domain"
    (originalSyntaxByteSpanV1 UInt64.size token)
  expectInvalid "position outside UInt64 domain"
    (originalSyntaxByteSpanV1 12 (originalAtom UInt64.size UInt64.size))

end Tests.Language.SourceSpan
