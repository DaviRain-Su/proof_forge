import Tests.Language.ParserSession
import ProofForgeV2.Language.Loader
import ProofForgeV2.Language.Syntax

/-!
ProgramV1 source-bound engineering gate (B2) — resident unit preflight.

Cheap root-inclusive unit boundaries for Fast/`dev-check` and full harness:
syntax depth/nodes, identifier components, and Root-aware program identity.

Heavy source-driven vectors (300-term nesting, 20_000-state node overflow,
exact 16 MiB accept / 16 MiB+1 reject, combined namespace+expression overflow)
stay in the subprocess CLI gate `scripts/program_v1_source_bounds` /
`just source-bounds` so the resident test process never materializes multi-MiB
or >100k-node fixtures.
-/

namespace Tests.Language.ProgramV1Bounds

open ProofForgeV2
open Lean

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def expectRender (error : CompileError) (expected : String) (label : String) : IO Unit :=
  let actual := CompileError.render error
  unless actual == expected do
    throw <| IO.userError s!"{label}: expected `{expected}`, got `{actual}`"

private def header : String :=
  "import ProofForgeV2\nopen ProofForgeV2.Language\n"

/-- S1-compatible Counter-like body for Root-identity namespace fixtures. -/
private def boundedProgramBody : String :=
  "program Bounded where\n" ++
  "  state count : UInt64\n" ++
  "  init(initial : UInt64) do\n" ++
  "    count := initial\n" ++
  "  view get() : UInt64 do\n" ++
  "    return count\n"

private def nestedNamespaceSource (depth : Nat) : String :=
  header ++
  String.intercalate "" (List.replicate depth "namespace N\n") ++
  boundedProgramBody ++
  String.intercalate "" (List.replicate depth "end N\n")

private def nestedIdentifierSource (parts : Nat) : String :=
  let name := String.intercalate "." (List.replicate parts "I")
  header ++
  "program Deep where\n  view get() : UInt64 do\n    return " ++ name ++ "\n"

private def linearSyntax (nodeCount : Nat) : Syntax := Id.run do
  let mut current := Syntax.atom .none "x"
  for _ in [1:nodeCount] do
    current := Syntax.node .none `ProofForgeV2.Tests.linearSyntax #[current]
  return current

private def wideSyntax (nodeCount : Nat) : Syntax :=
  Syntax.node .none `ProofForgeV2.Tests.wideSyntax <|
    Array.replicate (nodeCount - 1) (Syntax.atom .none "x")

private def deepIdentName (parts : Nat) : Name := Id.run do
  let mut name : Name := .anonymous
  for _ in [0:parts] do
    name := Name.str name "I"
  return name

private def identityNestingMessage : String :=
  s!"portable program identity exceeds nesting limit {Language.maxSyntaxNesting}"

private def syntaxNestingMessage : String :=
  s!"portable syntax exceeds nesting limit {Language.maxSyntaxNesting}"

private def syntaxNodeMessage : String :=
  s!"portable syntax exceeds node limit {Language.maxSyntaxNodes}"

private def identifierNestingMessage : String :=
  s!"portable identifier nesting exceeds limit {Language.maxSyntaxNesting}"

unsafe def run : IO Unit := do
  let session ← Tests.Language.ParserSession.shared

  expect (Language.maxSyntaxNesting == 256)
    "maxSyntaxNesting must equal 256"
  expect (Language.maxSyntaxNodes == 100000)
    "maxSyntaxNodes must equal 100000"

  -- Root-inclusive Syntax depth unit boundary (preflight is the product gate).
  match Language.preflightSyntax (linearSyntax Language.maxSyntaxNesting) with
  | .ok () => pure ()
  | .error error =>
      throw <| IO.userError s!"syntax depth 256 must accept: {CompileError.render error}"
  match Language.preflightSyntax (linearSyntax (Language.maxSyntaxNesting + 1)) with
  | .error error =>
      expectRender error s!"PF-BOUND-001: {syntaxNestingMessage}" "syntax depth 257"
  | .ok () => throw <| IO.userError "syntax depth 257 must reject"

  -- Root-inclusive Syntax node unit boundary.
  match Language.preflightSyntax (wideSyntax Language.maxSyntaxNodes) with
  | .ok () => pure ()
  | .error error =>
      throw <| IO.userError s!"syntax nodes 100000 must accept: {CompileError.render error}"
  match Language.preflightSyntax (wideSyntax (Language.maxSyntaxNodes + 1)) with
  | .error error =>
      expectRender error s!"PF-BOUND-001: {syntaxNodeMessage}" "syntax nodes 100001"
  | .ok () => throw <| IO.userError "syntax nodes 100001 must reject"

  -- Identifier component boundary via preflight (same check as product decode).
  let identAt := Syntax.ident .none "I".toRawSubstring (deepIdentName Language.maxSyntaxNesting) []
  let identOver :=
    Syntax.ident .none "I".toRawSubstring (deepIdentName (Language.maxSyntaxNesting + 1)) []
  match Language.preflightSyntax identAt with
  | .ok () => pure ()
  | .error error =>
      throw <| IO.userError s!"identifier 256 must accept: {CompileError.render error}"
  match Language.preflightSyntax identOver with
  | .error error =>
      expectRender error s!"PF-BOUND-001: {identifierNestingMessage}" "identifier 257"
  | .ok () => throw <| IO.userError "identifier 257 must reject"

  -- Source-driven identifier overflow through selectProgramV1 (small programs).
  match ← session.selectProgramV1
      (nestedIdentifierSource Language.maxSyntaxNesting) "<ident-256>" "Root" none with
  | .ok _ => pure ()
  | .error error =>
      throw <| IO.userError s!"source identifier 256 must parse: {CompileError.render error}"
  match ← session.selectProgramV1
      (nestedIdentifierSource (Language.maxSyntaxNesting + 1)) "<ident-257>" "Root" none with
  | .error error =>
      expectRender error s!"PF-BOUND-001: {identifierNestingMessage}" "source identifier 257"
  | .ok _ => throw <| IO.userError "source identifier 257 must reject"

  -- Root-inclusive program identity: module Root + 254 N + Bounded = 256 accept.
  match ← session.selectProgramV1
      (nestedNamespaceSource (Language.maxSyntaxNesting - 2)) "<identity-256>" "Root" none with
  | .ok source =>
      expect (source.programIdentity.components.toArray.size == Language.maxSyntaxNesting)
        "Root-inclusive identity at limit must have exactly 256 components"
      expect (source.program.name.raw == "Bounded")
        "identity-at-limit program name must remain Bounded"
  | .error error =>
      throw <| IO.userError s!"Root-inclusive identity 256 must accept: {CompileError.render error}"

  -- Root + 255 N + Bounded = 257 must be PF-BOUND-001 (not PF-SRC-INVALID).
  match ← session.selectProgramV1
      (nestedNamespaceSource (Language.maxSyntaxNesting - 1)) "<identity-257>" "Root" none with
  | .error error =>
      expectRender error s!"PF-BOUND-001: {identityNestingMessage}" "Root-inclusive identity 257"
  | .ok _ => throw <| IO.userError "Root-inclusive identity 257 must reject"

  -- Deeper namespace overLimit path stays PF-BOUND-001 with the same message.
  match ← session.parseProgramsV1
      (nestedNamespaceSource (Language.maxSyntaxNesting + 1)) "<identity-overlimit>" "Root" with
  | .error error =>
      expectRender error s!"PF-BOUND-001: {identityNestingMessage}" "namespace overLimit"
  | .ok _ => throw <| IO.userError "namespace overLimit must reject"

  -- Heavy vectors (300-term / 20k-state / 16 MiB / combined overflow) are covered
  -- only by scripts/program_v1_source_bounds (just source-bounds), not here.

  IO.println "Tests.Language.ProgramV1Bounds: ok"

end Tests.Language.ProgramV1Bounds
