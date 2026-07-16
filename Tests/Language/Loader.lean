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

end Tests.Language.Loader
