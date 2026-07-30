import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Examples.Counter
import ProofForgeV2.Language.Loader
import ProofForgeV2.Language.Syntax

namespace Tests.Language.ProgramSyntax

open ProofForgeV2
open ProofForgeV2.Core.Common
open ProofForgeV2.Source.NameComponentV1
open ProofForgeV2.Source.ValidatedSourceV1

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def isSha256Hex (value : String) : Bool :=
  value.length == 64 && value.toList.all fun char =>
    "0123456789abcdef".toList.contains char

private def linearSyntax (nodeCount : Nat) : Lean.Syntax := Id.run do
  let mut current := Lean.Syntax.atom .none "x"
  for _ in [1:nodeCount] do
    current := Lean.Syntax.node .none `ProofForgeV2.Tests.linearSyntax #[current]
  return current

private def wideSyntax (nodeCount : Nat) : Lean.Syntax :=
  Lean.Syntax.node .none `ProofForgeV2.Tests.wideSyntax <|
    Array.replicate (nodeCount - 1) (Lean.Syntax.atom .none "x")

private def mkProgramSource (namespaceName : String) : String :=
  "import ProofForgeV2\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "namespace " ++ namespaceName ++ "\n\n" ++
  "program Counter where\n" ++
  "  state count : UInt64\n\n" ++
  "  init(initial : UInt64) do\n" ++
  "    count := initial\n\n" ++
  "  entry increment(delta : UInt64) : UInt64 do\n" ++
  "    count := count + delta\n" ++
  "    return count\n\n" ++
  "  view get() : UInt64 do\n" ++
  "    return count\n\n" ++
  "end " ++ namespaceName ++ "\n"

private def aSource := mkProgramSource "A"
private def bSource := mkProgramSource "B"

private def deepUnarySource (depth : Nat) : String :=
  let expr := String.intercalate "" (List.replicate depth "!") ++ "true"
  "import ProofForgeV2\nopen ProofForgeV2.Language\nprogram Deep where\n  view get() : Bool do\n    return " ++ expr ++ "\n"

private def liftSourceHash (label : String) (result : Except String Digest) : IO Digest :=
  match result with
  | .ok digest => pure digest
  | .error message => throw <| IO.userError s!"{label}: {message}"

unsafe def run : IO Unit := do
  expect (ProofForgeV2.Language.maxSyntaxNodes == 100000 && ProofForgeV2.Language.maxSyntaxNesting == 256)
    "portable Syntax budgets must match SPEC-LANG-001"
  expect ((CompileError.resourceBound "test").code == "PF-BOUND-001")
    "resource-bound diagnostics must have a stable code"
  match ProofForgeV2.Language.preflightSyntax (linearSyntax ProofForgeV2.Language.maxSyntaxNesting) with
  | .ok () => pure ()
  | .error error => throw <| IO.userError s!"Syntax at the nesting limit must be accepted: {CompileError.render error}"
  match ProofForgeV2.Language.preflightSyntax (linearSyntax (ProofForgeV2.Language.maxSyntaxNesting + 1)) with
  | .error (.resourceBound _) => pure ()
  | _ => throw <| IO.userError "Syntax above the nesting limit must fail with PF-BOUND-001"
  let atNodeLimit := wideSyntax ProofForgeV2.Language.maxSyntaxNodes
  let overNodeLimit := wideSyntax (ProofForgeV2.Language.maxSyntaxNodes + 1)
  match ProofForgeV2.Language.preflightSyntax atNodeLimit with
  | .ok () => pure ()
  | .error error => throw <| IO.userError s!"Syntax at the node limit must be accepted: {CompileError.render error}"
  match ProofForgeV2.Language.preflightSyntax overNodeLimit with
  | .error (.resourceBound _) => pure ()
  | _ => throw <| IO.userError "Syntax above the node limit must fail with PF-BOUND-001"
  match ← Language.Loader.parseProgramsV1
      (deepUnarySource 300)
      "<program-syntax-deep>" "Root" with
  | .error (.resourceBound message) =>
      expect (message == s!"portable syntax exceeds nesting limit {ProofForgeV2.Language.maxSyntaxNesting}")
        "V1 loader must surface PF-BOUND-001 for over-nested source syntax"
  | .error error =>
      throw <| IO.userError s!"V1 deep syntax expected PF-BOUND-001, got {error.render}"
  | .ok _ => throw <| IO.userError "V1 deep syntax unexpectedly passed the loader"
  expect (Crypto.sha256Hex "".toUTF8 ==
      "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    "SHA-256 must match the empty-message reference vector"
  expect (Crypto.sha256Hex "abc".toUTF8 ==
      "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    "SHA-256 must match the abc reference vector"

  let counter ← match ← Language.Loader.selectProgramV1
      Examples.counterSourceText "<program-syntax-counter>"
      Examples.counterModuleNameV1 none with
  | .ok value => pure value
  | .error error => throw <| IO.userError s!"Counter V1 parse failed: {error.render}"
  let identity := counter.programIdentity.components.toArray.map (·.raw)
  expect (identity == #["Examples", "Counter", "ProofForgeV2", "Examples", "Counter"])
    "ProgramV1 identity must join module, namespace, and declaration raw components"
  let itemKinds := counter.program.items.map fun item =>
    match item with
    | .state s => ("state", s.name.raw)
    | .init _ => ("init", "")
    | .entry e => ("entry", e.name.raw)
    | .view v => ("view", v.name.raw)
    | _ => ("other", "")
  expect (itemKinds == #[("state", "count"), ("init", ""), ("entry", "increment"), ("view", "get")])
    "Counter ProgramV1 must retain state/init/entry/view source order"
  let sourceHash ← liftSourceHash "counter sourceHash" (sourceHashV1 counter)
  let renderedHash ← match renderDigest sourceHash with
  | .ok value => pure value
  | .error message => throw <| IO.userError message
  let hexPart := String.ofList (renderedHash.toList.drop "sha256:".length)
  expect (renderedHash.startsWith "sha256:" && isSha256Hex hexPart)
    "ProgramV1 source hash must be 64-character lower-case SHA-256 hex"

  let compiled ← match Compiler.compileValidatedSourceV1 counter with
  | .ok value => pure value
  | .error error => throw <| IO.userError error.render
  expect (Compiler.CompiledSemanticV1.sourceDigestOf compiled == sourceHash)
    "compiled carrier must bind the canonical ProgramV1 source digest"
  expect (Compiler.CompiledSemanticV1.artifactProgramNameOf compiled == "Counter")
    "compiled artifact name must come from the semantic qualified-name suffix"
  let semanticData ← match ProofForgeV2.Semantic.WireV1.validateSemanticProgramV1
      (Compiler.CompiledSemanticV1.semanticV1Of compiled) with
  | .ok value => pure value
  | .error error => throw <| IO.userError s!"Counter semantic carrier invalid: {repr error}"
  expect (semanticData.requirements.items.map (·.id) ==
      ProofForgeV2.Semantic.RequirementsV1.s2CatalogIdsWireOrderV1)
    "semantic requirements must be the canonical Counter S2 request set"

  let aCounter ← match ← Language.Loader.selectProgramV1
      aSource "<program-syntax-a>" "A" none with
  | .ok value => pure value
  | .error error => throw <| IO.userError error.render
  let bCounter ← match ← Language.Loader.selectProgramV1
      bSource "<program-syntax-b>" "B" none with
  | .ok value => pure value
  | .error error => throw <| IO.userError error.render
  expect (aCounter.program.name.raw == "Counter" && bCounter.program.name.raw == "Counter")
    "artifact names must remain short"
  expect (aCounter.programIdentity.components.toArray.map (·.raw) == #["A", "Counter"])
    "namespace must participate in program identity"
  expect (bCounter.programIdentity.components.toArray.map (·.raw) == #["B", "Counter"])
    "namespace must participate in program identity"
  let aHash ← liftSourceHash "aCounter hash" (sourceHashV1 aCounter)
  let bHash ← liftSourceHash "bCounter hash" (sourceHashV1 bCounter)
  expect (aHash != bHash)
    "fully-qualified identity must participate in source hashing"

end Tests.Language.ProgramSyntax
