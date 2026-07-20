import ProofForgeV2.Language.Syntax

namespace Tests.Language.SourceBoundsAcceptance
open ProofForgeV2
open ProofForgeV2.Language

private def expect (c : Bool) (m : String) : IO Unit :=
  unless c do throw <| IO.userError m

private def linearSyntax (depth : Nat) : Lean.Syntax := Id.run do
  let mut current := Lean.Syntax.atom .none "x"
  for _ in [1:depth] do
    current := Lean.Syntax.node .none `ProofForgeV2.Tests.linearSyntax #[current]
  return current

private def wideSyntax (nodeCount : Nat) : Lean.Syntax :=
  Lean.Syntax.node .none `ProofForgeV2.Tests.wideSyntax <|
    Array.replicate (nodeCount - 1) (Lean.Syntax.atom .none "x")

private def repeatedName (partCount : Nat) : Lean.Name := Id.run do
  let mut name := Lean.Name.anonymous
  for _ in [:partCount] do
    name := Lean.Name.mkStr name "N"
  return name

private def exactNest : String :=
  "PF-BOUND-001: portable syntax exceeds nesting limit 256"

private def exactNode : String :=
  "PF-BOUND-001: portable syntax exceeds node limit 100000"

private def exactIdentity : String :=
  "PF-BOUND-001: portable program identity exceeds nesting limit 256"

private def exactIdent : String :=
  "PF-BOUND-001: portable identifier nesting exceeds limit 256"

private def expectExactError (result : Except String α) (want label : String) : IO Unit :=
  match result with
  | .error message => expect (message == want) s!"{label}: got {message}"
  | .ok _ => throw <| IO.userError s!"{label}: unexpectedly succeeded"

private def expectCompileExact (result : CompileResult α) (want label : String) : IO Unit :=
  match result with
  | .error error => expect (error.render == want) s!"{label}: got {error.render}"
  | .ok _ => throw <| IO.userError s!"{label}: unexpectedly succeeded"

/-- TST-SRC-002 unit packaging: direct preflight/decoder bounds; heavy path = just dsl-negative. -/
def run : IO Unit := do
  expect (maxSyntaxNesting == 256 && maxSyntaxNodes == 100000) "constants"
  expect ((CompileError.resourceBound "test").code == "PF-BOUND-001") "code"
  match preflightSyntax (linearSyntax 256) with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"linear 256: {e.render}"
  expectCompileExact (preflightSyntax (linearSyntax 257)) exactNest "linear 257"
  match preflightSyntax (wideSyntax 100000) with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"wide 100000: {e.render}"
  expectCompileExact (preflightSyntax (wideSyntax 100001)) exactNode "wide 100001"
  let overNest := linearSyntax 257
  expectExactError (decodeType overNest) exactNest "decodeType"
  expectExactError (decodeParam overNest) exactNest "decodeParam"
  expectExactError (decodeExpr overNest) exactNest "decodeExpr"
  expectExactError (decodeStatement overNest) exactNest "decodeStatement"
  expectExactError (decodeItem overNest) exactNest "decodeItem"
  expectExactError (decodeProgramCommand .anonymous overNest) exactNest "decodeProgram nest"
  expectExactError (decodeProgramCommand .anonymous (wideSyntax 100001)) exactNode
    "decodeProgram nodes"
  match preflightProgramIdentity (repeatedName 255) `BoundProbe with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"identity 255+1: {e.render}"
  expectCompileExact (preflightProgramIdentity (repeatedName 256) `BoundProbe) exactIdentity
    "identity 256+program"
  let idOk := Lean.Syntax.ident .none "N".toRawSubstring (repeatedName 256) []
  let idBad := Lean.Syntax.ident .none "N".toRawSubstring (repeatedName 257) []
  match preflightSyntax idOk with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"ident 256: {e.render}"
  expectCompileExact (preflightSyntax idBad) exactIdent "ident 257"

end Tests.Language.SourceBoundsAcceptance
