import ProofForgeV2.Examples.Counter
import ProofForgeV2.Language.Loader
import ProofForgeV2.Compiler.Pipeline

namespace ExportA

open ProofForgeV2.Language

program Counter where
  view get() : UInt64 do
    return 1

end ExportA

namespace ExportB

open ProofForgeV2.Language

program Counter where
  view get() : UInt64 do
    return 2

end ExportB

namespace Tests.Language.Export

open ProofForgeV2
open ProofForgeV2.Source

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def expectCode (result : Except CompileError α) (code : String) (message : String) :
    IO Unit :=
  match result with
  | .error error =>
      expect (error.code == code) s!"{message}: got {error.render}"
  | .ok _ => throw <| IO.userError message

private def isSha256Hex (value : String) : Bool :=
  value.length == 64 && value.toList.all fun char =>
    "0123456789abcdef".toList.contains char

/-- TST-SRC-006/007/008 + TST-DIAG-001 export/loader/diagnostic slice. -/
unsafe def run : IO Unit := do
  -- TST-SRC-006/007: stable attribute export identity + sourceHash schema.
  expect (ExportA.Counter.name == "Counter" && ExportB.Counter.name == "Counter")
    "export short name is stable"
  expect (ExportA.Counter.qualifiedName == "ExportA.Counter" &&
      ExportB.Counter.qualifiedName == "ExportB.Counter")
    "namespace participates in export identity"
  expect (ExportA.Counter.sourceHash != ExportB.Counter.sourceHash)
    "distinct modules must not collide on sourceHash"
  expect (isSha256Hex ExportA.Counter.sourceHash && isSha256Hex ExportB.Counter.sourceHash)
    "sourceHash is 64 lower-case hex"
  let again := ExportA.Counter.sourceHash
  expect (again == ExportA.Counter.sourceHash) "sourceHash is deterministic"
  expect (Examples.counter.qualifiedName == "ProofForgeV2.Examples.Counter")
    "elaborated Counter keeps fully-qualified export identity"
  match Compiler.compile Examples.counter with
  | .ok semantic =>
      expect (semantic.sourceHash == Examples.counter.sourceHash)
        "semantic provenance retains sourceHash"
      expect (semantic.qualifiedName == Examples.counter.qualifiedName)
        "semantic provenance retains qualifiedName"
  | .error error => throw <| IO.userError error.render

  -- TST-SRC-008: multi-program selection.
  let multiple :=
    "import ProofForgeV2\nopen ProofForgeV2.Language\n" ++
    "namespace X\nprogram One where\n  view get() : UInt64 do\n    return 1\nend X\n" ++
    "namespace Y\nprogram Two where\n  view get() : UInt64 do\n    return 2\nend Y\n"
  expectCode (← Language.Loader.selectProgram multiple "<multi>" none) "PF-EXPORT-002"
    "multiple programs without --program must be PF-EXPORT-002"
  match ← Language.Loader.selectProgram multiple "<multi>" (some "Y.Two") with
  | .ok selected =>
      expect (selected.qualifiedName == "Y.Two") "explicit selection uses qualified name"
      expect (selected.name == "Two") "selected short name is stable"
  | .error error => throw <| IO.userError error.render

  let duplicate :=
    "import ProofForgeV2\nopen ProofForgeV2.Language\n" ++
    "namespace Dup\nprogram Same where\n  view get() : UInt64 do\n    return 1\n" ++
    "program Same where\n  view get() : UInt64 do\n    return 2\nend Dup\n"
  expectCode (← Language.Loader.parsePrograms duplicate "<dup>") "PF-EXPORT-001"
    "duplicate qualified export must be PF-EXPORT-001"

  -- TST-DIAG-001: stable diagnostic codes/render shape.
  match ← Language.Loader.selectProgram multiple "<multi>" none with
  | .error error =>
      expect (error.render.startsWith "PF-EXPORT-002:")
        s!"diagnostic render must be code: message, got {error.render}"
  | .ok _ => throw <| IO.userError "expected ambiguous export diagnostic"

end Tests.Language.Export
