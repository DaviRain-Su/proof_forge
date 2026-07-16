import ProofForgeV2.Language.Loader
import ProofForgeV2.Examples.Counter
import ProofForgeV2.Compiler.Pipeline

namespace Tests.Language.Loader

open ProofForgeV2 System

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def expectRejected (result : Except CompileError α) (message : String) : IO Unit :=
  match result with
  | .error _ => pure ()
  | .ok _ => throw <| IO.userError message

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

private def wideProgramSource (stateCount : Nat) : String :=
  "import ProofForgeV2\nopen ProofForgeV2.Language\nprogram Wide where\n" ++
  String.intercalate "" (List.replicate stateCount "  state cell : UInt64\n") ++
  "  view get() : UInt64 do\n    return 0\n"

unsafe def run : IO Unit := do
  let decoded ← Language.Loader.selectProgram counterSource "<counter>" (some "ProofForgeV2.Examples.Counter")
  match decoded with
  | .ok contractProgram =>
      expect (contractProgram == Examples.counter)
        s!"Lean parser decoding and command elaboration must produce the same source AST\ndecoded={repr contractProgram}\nelaborated={repr Examples.counter}"
  | .error error => throw <| IO.userError error.render

  let marker := FilePath.mk "build/v2/loader-must-not-execute"
  if ← marker.pathExists then IO.FS.removeFile marker
  let malicious := "import ProofForgeV2\nrun_cmd IO.FS.writeFile \"build/v2/loader-must-not-execute\" \"executed\"\n"
  expectRejected (← Language.Loader.parsePrograms malicious "<malicious>")
    "arbitrary Lean commands must be rejected"
  expect (!(← marker.pathExists)) "parsing must never execute run_cmd"

  let deepUnsupportedImport := "import " ++
    String.intercalate "." (List.replicate (Language.maxSyntaxNesting + 1) "N") ++ "\n"
  match ← Language.Loader.parsePrograms deepUnsupportedImport "<deep-import>" with
  | .error (.invalidProgram message) =>
      expect (message == "unsupported import; only ProofForgeV2 is allowed")
        "unsupported imports must not recursively render attacker-controlled qualified names"
  | .error error => throw <| IO.userError s!"deep unsupported import returned {error.render}"
  | .ok _ => throw <| IO.userError "deep unsupported import unexpectedly passed"

  let duplicateInit := "import ProofForgeV2\nopen ProofForgeV2.Language\nprogram Duplicate where\n  init() do\n  init() do\n  view get() : UInt64 do\n    return 0\n"
  expectRejected (← Language.Loader.parsePrograms duplicateInit "<duplicate-init>")
    "duplicate initializers must be rejected"

  let multiple := "import ProofForgeV2\nopen ProofForgeV2.Language\nnamespace A\nprogram One where\n  view get() : UInt64 do\n    return 1\nend A\nnamespace B\nprogram Two where\n  view get() : UInt64 do\n    return 2\nend B\n"
  expectRejected (← Language.Loader.selectProgram multiple "<multiple>" none)
    "multiple programs must require an explicit qualified name"
  match ← Language.Loader.selectProgram multiple "<multiple>" (some "B.Two") with
  | .ok contractProgram => expect (contractProgram.qualifiedName == "B.Two") "qualified selection failed"
  | .error error => throw <| IO.userError error.render

  let stateless := "import ProofForgeV2\nopen ProofForgeV2.Language\nprogram PrivateSum4 where\n  entry sum(private a : UInt64, private b : UInt64, private c : UInt64, private d : UInt64) : UInt64 do\n    return a + b\n"
  match ← Language.Loader.selectProgram stateless "<stateless>" none with
  | .ok contractProgram =>
      expect contractProgram.state.isEmpty "stateless programs must remain valid"
      match Compiler.compile contractProgram with
      | .ok semanticProgram =>
          expect (semanticProgram.requirements.contains .privateWitness)
            "private visibility must survive parsing and semantic compilation"
      | .error error => throw <| IO.userError error.render
  | .error error => throw <| IO.userError error.render

  let withKind := "import ProofForgeV2\nopen ProofForgeV2.Language\nprogram Invalid : contract where\n  view get() : UInt64 do\n    return 0\n"
  expectRejected (← Language.Loader.parsePrograms withKind "<kind>")
    "source-level kind syntax must remain invalid"

  let tooLarge := "import ProofForgeV2\nopen ProofForgeV2.Language\nprogram TooLarge where\n  view get() : UInt64 do\n    return 18446744073709551616\n"
  expectRejected (← Language.Loader.parsePrograms tooLarge "<u64-overflow>")
    "UInt64 literals above the maximum must be rejected"

  match ← Language.Loader.parsePrograms (nestedAdditionSource 300) "<deep-syntax>" with
  | .error (.resourceBound _) => pure ()
  | .error error => throw <| IO.userError s!"deep portable syntax must use PF-BOUND-001, found {CompileError.render error}"
  | .ok _ => throw <| IO.userError "deep portable syntax unexpectedly passed the loader"

  match ← Language.Loader.selectProgram
      (nestedNamespaceSource (Language.maxSyntaxNesting - 1)) "<namespace-limit>" none with
  | .ok contractProgram =>
      expect (contractProgram.name == "Bounded")
        "qualified program identity at the nesting limit must pass the loader"
  | .error error => throw <| IO.userError s!"namespace limit unexpectedly failed: {error.render}"
  match ← Language.Loader.parsePrograms
      (nestedNamespaceSource Language.maxSyntaxNesting) "<namespace-over-limit>" with
  | .error (.resourceBound _) => pure ()
  | .error error => throw <| IO.userError s!"namespace overflow must use PF-BOUND-001, found {error.render}"
  | .ok _ => throw <| IO.userError "namespace identity above the limit unexpectedly passed"

  match ← Language.Loader.selectProgram
      (unwoundNamespaceSource
        (Language.maxSyntaxNesting + 1) (Language.maxSyntaxNesting - 1))
      "<namespace-unwound-at-limit>" none with
  | .ok contractProgram =>
      expect (contractProgram.name == "Bounded")
        "a transient over-limit namespace must pass after unwinding to a legal program identity"
      let expectedQualifiedName := String.intercalate "." <|
        List.replicate (Language.maxSyntaxNesting - 1) "N" ++ ["Bounded"]
      expect (contractProgram.qualifiedName == expectedQualifiedName)
        "unwinding must restore the exact bounded namespace prefix"
  | .error error => throw <| IO.userError <|
      s!"namespace unwound to the identity limit unexpectedly failed: {error.render}"

  match ← Language.Loader.parsePrograms
      (overLimitNamespaceAndExpressionSource
        (Language.maxSyntaxNesting + 1) 300) "<namespace-and-syntax-over-limit>" with
  | .error (.resourceBound message) =>
      expect (message == s!"portable syntax exceeds nesting limit {Language.maxSyntaxNesting}")
        "portable Syntax preflight must win before namespace identity rejection"
  | .error error => throw <| IO.userError <|
      s!"combined namespace/Syntax overflow returned the wrong error: {error.render}"
  | .ok _ => throw <| IO.userError "combined namespace/Syntax overflow unexpectedly passed"

  match ← Language.Loader.parsePrograms (wideProgramSource 20000) "<wide-syntax>" with
  | .error (.resourceBound _) => pure ()
  | .error error => throw <| IO.userError s!"wide portable syntax must use PF-BOUND-001, found {error.render}"
  | .ok _ => throw <| IO.userError "wide portable syntax unexpectedly passed the loader"

end Tests.Language.Loader
