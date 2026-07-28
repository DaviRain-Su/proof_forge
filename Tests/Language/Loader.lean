import Tests.Language.ParserSession
import ProofForgeV2.Compiler.Pipeline

namespace Tests.Language.Loader

open ProofForgeV2 System
open ProofForgeV2.Core.Common
open ProofForgeV2.Source.AstV1

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def expectRejected (result : Except CompileError α) (message : String) : IO Unit :=
  match result with
  | .error _ => pure ()
  | .ok _ => throw <| IO.userError message

private def withCapturedStdout (act : IO α) : IO (α × String) := do
  let (stdout, result) ← IO.FS.withIsolatedStreams act (isolateStderr := false)
  pure (result, stdout)

private def counterSource : String :=
  "import ProofForgeV2\n\n" ++
  "namespace ProofForgeV2.Examples\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program Counter where\n" ++
  "  state count : UInt64\n\n" ++
  "  init(initial : UInt64) do\n" ++
  "    count := initial\n\n" ++
  "  entry increment(delta : UInt64) : UInt64 do\n" ++
  "    count := count + delta\n" ++
  "    return count\n\n" ++
  "  view get() : UInt64 do\n" ++
  "    return count\n\n" ++
  "end ProofForgeV2.Examples\n"

private def nestedAdditionSource (terms : Nat) : String :=
  "import ProofForgeV2\nopen ProofForgeV2.Language\n" ++
  "program Deep where\n  view get() : UInt64 do\n    return " ++
  String.intercalate " + " (List.replicate terms "1") ++ "\n"

private def nestedNamespaceSource (depth : Nat) : String :=
  "import ProofForgeV2\nopen ProofForgeV2.Language\n" ++
  String.intercalate "" (List.replicate depth "namespace N\n") ++
  "program Bounded where\n  view get() : UInt64 do\n    return 0\n" ++
  String.intercalate "" (List.replicate depth "end N\n")

private def unwoundNamespaceSource (peakDepth retainedDepth : Nat) : String :=
  "import ProofForgeV2\nopen ProofForgeV2.Language\n" ++
  String.intercalate "" (List.replicate peakDepth "namespace N\n") ++
  String.intercalate "" (List.replicate (peakDepth - retainedDepth) "end N\n") ++
  "program Bounded where\n  view get() : UInt64 do\n    return 0\n" ++
  String.intercalate "" (List.replicate retainedDepth "end N\n")

private def overLimitNamespaceAndExpressionSource (depth terms : Nat) : String :=
  "import ProofForgeV2\nopen ProofForgeV2.Language\n" ++
  String.intercalate "" (List.replicate depth "namespace N\n") ++
  "program Deep where\n  view get() : UInt64 do\n    return " ++
  String.intercalate " + " (List.replicate terms "1") ++ "\n" ++
  String.intercalate "" (List.replicate depth "end N\n")

private def qualifiedNamespaceOverflowSource (parts : Nat) : String :=
  "import ProofForgeV2\nopen ProofForgeV2.Language\n" ++
  "namespace Outer\nnamespace " ++
  String.intercalate "." (List.replicate parts "N") ++ "\n" ++
  "program Bounded where\n  view get() : UInt64 do\n    return 0\n" ++
  "end\nend Outer\n"

unsafe def run : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let counter ← match ← session.selectProgramV1 counterSource "<counter>"
      "ProofForgeV2.Examples" none with
  | .ok source =>
      expect (source.program.name.raw == "Counter")
        "Counter V1 must retain its source name"
      expect (source.program.items.size == 4)
        "Counter V1 must retain state/init/entry/view source order"
      pure source
  | .error error => throw <| IO.userError error.render

  let marker := FilePath.mk "build/v2/loader-must-not-execute"
  if ← marker.pathExists then IO.FS.removeFile marker
  let malicious := "import ProofForgeV2\nrun_cmd IO.FS.writeFile \"build/v2/loader-must-not-execute\" \"executed\"\n"
  expectRejected (← session.parseProgramsV1 malicious "<malicious>" "Root")
    "arbitrary Lean commands must be rejected"
  expect (!(← marker.pathExists)) "parsing must never execute run_cmd"

  let withKind := "import ProofForgeV2\nopen ProofForgeV2.Language\nprogram Invalid : contract where\n  view get() : UInt64 do\n    return 0\n"
  let (res, _stdout) ← withCapturedStdout (session.parseProgramsV1 withKind "<kind>" "Root")
  expectRejected res "source-level kind syntax must remain invalid"

  let deepUnsupportedImport := "import " ++
    String.intercalate "." (List.replicate (Language.maxSyntaxNesting + 1) "N") ++ "\n"
  match ← session.parseProgramsV1 deepUnsupportedImport "<deep-import>" "Root" with
  | .error (.invalidProgram message) =>
      expect (message == "unsupported import; only ProofForgeV2 is allowed")
        "unsupported imports must not recursively render attacker-controlled qualified names"
  | .error error => throw <| IO.userError s!"deep unsupported import returned {error.render}"
  | .ok _ => throw <| IO.userError "deep unsupported import unexpectedly passed"

  let duplicateInit := "import ProofForgeV2\nopen ProofForgeV2.Language\nprogram Duplicate where\n  init() do\n  init() do\n  view get() : UInt64 do\n    return 0\n"
  expectRejected (← session.parseProgramsV1 duplicateInit "<duplicate-init>" "Root")
    "duplicate initializers must be rejected"

  let multiple := "import ProofForgeV2\nopen ProofForgeV2.Language\nnamespace A\nprogram One where\n  view get() : UInt64 do\n    return 1\nend A\nnamespace B\nprogram Two where\n  view get() : UInt64 do\n    return 2\nend B\n"
  expectRejected (← session.selectProgramV1 multiple "<multiple>" "Product.Multi" none)
    "multiple programs must require an explicit qualified name"
  match ← session.selectProgramV1 multiple "<multiple>" "Product.Multi"
      (some "Product.Multi.B.Two") with
  | .ok source =>
      expect (source.programIdentity.components.toArray.map (·.raw) ==
        #["Product", "Multi", "B", "Two"]) "qualified selection failed"
  | .error error => throw <| IO.userError error.render

  -- Stateless private params parse, but explicit disclosure rejects returning
  -- private values through a public entry result (product CheckV1 gate).
  let stateless := "import ProofForgeV2\nopen ProofForgeV2.Language\nprogram PrivateSum4 where\n  entry sum(private a : UInt64, private b : UInt64, private c : UInt64, private d : UInt64) : UInt64 do\n    return a + b\n"
  match ← session.selectProgramV1 stateless "<stateless>" "Root" none with
  | .ok source =>
      expect (source.program.items.all fun item =>
        match item with | .entry _ => true | _ => false)
        "stateless programs must remain valid"
      let hasPrivateParam := source.program.items.any fun item =>
        match item with
        | .entry e => e.params.any (·.visibility == .private_)
        | _ => false
      expect hasPrivateParam "private parameter visibility must survive parsing"
      match Compiler.compileValidatedSourceV1 source with
      | .error (.visibilityViolation message) =>
          expect (message.contains "disclosure violation: cannot flow 'private' into 'public'")
            s!"private→public return must use disclosure wire detail, got {message}"
      | .error other =>
          throw <| IO.userError
            s!"private→public return must fail closed with PF-VIS-001, got {other.render}"
      | .ok _ =>
          throw <| IO.userError
            "private→public return must not compile through the product Typed gate"
  | .error error => throw <| IO.userError error.render

  let tooLarge := "import ProofForgeV2\nopen ProofForgeV2.Language\nprogram TooLarge where\n  view get() : UInt64 do\n    return 18446744073709551616\n"
  match ← session.selectProgramV1 tooLarge "<u64-overflow>" "Root" none with
  | .ok source =>
      match Compiler.compileValidatedSourceV1 source with
      | .ok _ => throw <| IO.userError "UInt64 literals above the maximum must be rejected"
      | .error _ => pure ()
  | .error _ => pure ()

  match ← session.parseProgramsV1 (nestedAdditionSource 300) "<deep-syntax>" "Root" with
  | .error (.resourceBound _) => pure ()
  | .error error => throw <| IO.userError s!"deep portable syntax must use PF-BOUND-001, found {CompileError.render error}"
  | .ok _ => throw <| IO.userError "deep portable syntax unexpectedly passed the loader"

  match ← session.selectProgramV1
      (nestedNamespaceSource (Language.maxSyntaxNesting - 2)) "<namespace-limit>" "Root" none with
  | .ok source =>
      expect (source.program.name.raw == "Bounded")
        "qualified program identity at the nesting limit must pass the loader"
  | .error error => throw <| IO.userError s!"namespace limit unexpectedly failed: {error.render}"
  match ← session.parseProgramsV1
      (nestedNamespaceSource (Language.maxSyntaxNesting + 1)) "<namespace-over-limit>" "Root" with
  | .error (.resourceBound _) => pure ()
  | .error error => throw <| IO.userError s!"namespace overflow must use PF-BOUND-001, found {error.render}"
  | .ok _ => throw <| IO.userError "namespace identity above the limit unexpectedly passed"

  match ← session.parseProgramsV1
      (qualifiedNamespaceOverflowSource Language.maxSyntaxNesting)
      "<qualified-namespace-over-limit>" "Root" with
  | .error (.resourceBound _) => pure ()
  | .error error => throw <| IO.userError <|
      s!"qualified namespace overflow must use PF-BOUND-001, found {error.render}"
  | .ok _ => throw <| IO.userError "qualified namespace overflow unexpectedly passed"

  match ← session.selectProgramV1
      (unwoundNamespaceSource
        (Language.maxSyntaxNesting + 1) (Language.maxSyntaxNesting - 2))
      "<namespace-unwound-at-limit>" "Root" none with
  | .ok source =>
      expect (source.program.name.raw == "Bounded")
        "a transient over-limit namespace must pass after unwinding to a legal program identity"
      let expectedComponents := List.replicate (Language.maxSyntaxNesting - 2) "N" ++ ["Bounded"]
      expect ((source.programIdentity.components.toArray.map (·.raw)).toList ==
        ("Root" :: expectedComponents))
        "unwinding must restore the exact bounded namespace prefix"
  | .error error => throw <| IO.userError <|
      s!"namespace unwound to the identity limit unexpectedly failed: {error.render}"

  match ← session.parseProgramsV1
      (overLimitNamespaceAndExpressionSource
        (Language.maxSyntaxNesting + 1) 300) "<namespace-and-syntax-over-limit>" "Root" with
  | .error (.resourceBound message) =>
      expect (message == s!"portable syntax exceeds nesting limit {Language.maxSyntaxNesting}")
        "portable Syntax preflight must win before namespace identity rejection"
  | .error error => throw <| IO.userError <|
      s!"combined namespace/Syntax overflow returned the wrong error: {error.render}"
  | .ok _ => throw <| IO.userError "combined namespace/Syntax overflow unexpectedly passed"

  let semanticCounter ← match Compiler.compileValidatedSourceV1 counter with
    | .ok value => pure (Compiler.CompiledProgramV1.alphaResidualOf value)
    | .error error => throw <| IO.userError error.render
  expect (semanticCounter.state.map (·.name) == #["count"] &&
      semanticCounter.entries.map (·.name) == #["increment", "get"])
    "ProgramV1 typing must preserve Counter state and callables"

end Tests.Language.Loader
