import Lean.Util.Path
import ProofForgeV2.Language.Syntax
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
    (source : String) (startByte endByte : Nat)
    (value : String := "token") : Lean.Syntax :=
  .atom (.original
    (.mk source (.mk startByte) (.mk startByte)) (.mk startByte)
    (.mk source (.mk endByte) (.mk endByte)) (.mk endByte)) value

private def syntheticAtom
    (startByte endByte : Nat) (canonical : Bool) : Lean.Syntax :=
  .atom (.synthetic (.mk startByte) (.mk endByte) canonical) "token"

private unsafe def parserEnvironment : IO Lean.Environment := do
  Lean.enableInitializersExecution
  Lean.initSearchPath (← Lean.findSysroot "lean")
  Lean.importModules #[{ module := `ProofForgeV2.Language.Syntax }] {} 0
    (loadExts := true)

unsafe def run : IO Unit := do
  let tokenSource := "    token   "
  let token := originalAtom tokenSource 4 9
  let span ← liftSpan "original atom" (originalSyntaxByteSpanV1 tokenSource token)
  expect (span == { startByte := 4, endByte := 9 })
    "original token positions must become an exact half-open byte span"

  let wrappedSource := "_é_x"
  let wrapped := Lean.Syntax.node .none `ProofForgeV2.Tests.SourceSpan #[
    originalAtom wrappedSource 1 3 "é",
    Lean.Syntax.node .none Lean.nullKind #[],
    originalAtom wrappedSource 4 5 "x"
  ]
  let wrappedSpan ← liftSpan "parser node with optional empty field"
    (originalSyntaxByteSpanV1 wrappedSource wrapped)
  expect (wrappedSpan == { startByte := 1, endByte := 5 })
    "parser nodes must use the first and last original UTF-8 byte positions"
  let multibyteSpan ← liftSpan "multibyte token"
    (originalSyntaxByteSpanV1 "é" (originalAtom "é" 0 2 "é"))
  expect (multibyteSpan == { startByte := 0, endByte := 2 })
    "source offsets must count UTF-8 bytes rather than Unicode scalar values"

  expectInvalid "missing root"
    (originalSyntaxByteSpanV1 "" Lean.Syntax.missing)
  let descendantMissing := Lean.Syntax.node .none `ProofForgeV2.Tests.SourceSpan #[
    originalAtom "ab" 0 1 "a", Lean.Syntax.missing,
    originalAtom "ab" 1 2 "b"
  ]
  expectInvalid "missing descendant"
    (originalSyntaxByteSpanV1 "ab" descendantMissing)
  expectInvalid "non-canonical synthetic syntax"
    (originalSyntaxByteSpanV1 tokenSource (syntheticAtom 4 9 false))
  expectInvalid "canonical synthetic syntax"
    (originalSyntaxByteSpanV1 tokenSource (syntheticAtom 4 9 true))
  let mixedTree := Lean.Syntax.node .none `ProofForgeV2.Tests.SourceSpan #[
    originalAtom "abc" 0 1 "a", syntheticAtom 1 2 true,
    originalAtom "abc" 2 3 "b"
  ]
  expectInvalid "synthetic descendant"
    (originalSyntaxByteSpanV1 "abc" mixedTree)
  expectInvalid "reversed source positions"
    (originalSyntaxByteSpanV1 tokenSource (originalAtom tokenSource 9 4))
  expectInvalid "position beyond source snapshot"
    (originalSyntaxByteSpanV1 "short" token)
  expectInvalid "position outside UInt64 domain"
    (originalSyntaxByteSpanV1 tokenSource
      (originalAtom tokenSource UInt64.size UInt64.size))
  expectInvalid "snapshot identity mismatch"
    (originalSyntaxByteSpanV1 "    other   " token)
  expectInvalid "UTF-8 continuation-byte start"
    (originalSyntaxByteSpanV1 "é" (originalAtom "é" 1 2 "bad"))
  expectInvalid "atom without original source info"
    (originalSyntaxByteSpanV1 "x" (.atom .none "x"))
  expectInvalid "identifier without original source info"
    (originalSyntaxByteSpanV1 "x"
      (.ident .none "x".toRawSubstring `x []))
  expectInvalid "source-annotated node"
    (originalSyntaxByteSpanV1 "x"
      (.node (.synthetic (.mk 0) (.mk 1) true) `ProofForgeV2.Tests.SourceSpan
        #[originalAtom "x" 0 1 "x"]))
  expectInvalid "empty parser node has no token span"
    (originalSyntaxByteSpanV1 "" (.node .none Lean.nullKind #[]))
  let reversedInterior := Lean.Syntax.node .none `ProofForgeV2.Tests.SourceSpan #[
    originalAtom "abcdef" 0 1 "a",
    originalAtom "abcdef" 4 3 "bad",
    originalAtom "abcdef" 5 6 "f"
  ]
  expectInvalid "reversed interior token"
    (originalSyntaxByteSpanV1 "abcdef" reversedInterior)
  let outOfOrderInterior := Lean.Syntax.node .none `ProofForgeV2.Tests.SourceSpan #[
    originalAtom "abcdef" 0 1 "a",
    originalAtom "abcdef" 4 5 "e",
    originalAtom "abcdef" 2 3 "c"
  ]
  expectInvalid "out-of-order interior token"
    (originalSyntaxByteSpanV1 "abcdef" outOfOrderInterior)

  let modulePrefix :=
    "import ProofForgeV2\nopen ProofForgeV2.Language\n\n"
  let programText :=
    "program SpanProbe where\n  view get() : UInt64 do\n    return 0"
  let moduleSource := modulePrefix ++ programText ++ "\n/- trailing comment -/\n"
  let environment ← parserEnvironment
  let parsed ← Lean.Parser.testParseModule environment "<source-span>" moduleSource
  match parsed.getArgs with
  | #[_, commands] =>
      match commands.getArgs.find? fun command =>
          command.getKind == ``ProofForgeV2.Language.programDecl with
      | some programSyntax =>
          let parsedSpan ← liftSpan "real parser program"
            (originalSyntaxByteSpanV1 moduleSource programSyntax)
          expect (parsedSpan == {
              startByte := UInt64.ofNat modulePrefix.toUTF8.size
              endByte := UInt64.ofNat (modulePrefix ++ programText).toUTF8.size
            })
            "real parser span must exclude leading layout and trailing comment/newline"
      | none => throw <| IO.userError "real parser fixture did not contain a program command"
  | _ => throw <| IO.userError "real parser fixture returned an invalid module tree"

end Tests.Language.SourceSpan
