import ProofForgeV2.Core.Source
import ProofForgeV2.Examples.Counter
import ProofForgeV2.Compiler.Pipeline

namespace Tests.Language.SourceIdentity

open ProofForgeV2
open ProofForgeV2.Source

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def expectErrorCode (result : CompileResult α) (code : String) (message : String) : IO Unit :=
  match result with
  | .error error =>
      expect (error.code == code) s!"{message}: got {error.render}"
  | .ok _ => throw <| IO.userError message

/-- TST-SRC-001/002: token stream, spans, NodeId canonicalization, and source limits. -/
def run : IO Unit := do
  -- Token + span canonicalization on a portable DSL fragment.
  let source := "program Counter where\n  // comment\n  view get() : UInt64 do\n    return 0\n"
  let tokens ← match tokenize source with
    | .ok value => pure value
    | .error error => throw <| IO.userError error.render
  expect (tokens.size ≥ 8) "tokenizer must emit portable tokens"
  expect (tokens.back?.map (·.kind) == some TokenKind.eof) "token stream must end with eof"
  match tokens[0]? with
  | some token =>
      expect (token.kind == .keyword "program") "first token must be program keyword"
      expect (token.span.byteStart == 0 && token.span.line == 1 && token.span.column == 1)
        "program keyword span must start at file origin"
  | none => throw <| IO.userError "missing first token"
  -- Comments are skipped and do not create tokens or break span order.
  expect (!tokens.any fun token =>
      match token.kind with
      | .ident text => text == "comment"
      | .keyword text => text == "comment"
      | _ => false) "comment text must not become a token"
  let again ← match tokenize source with
    | .ok value => pure value
    | .error error => throw <| IO.userError error.render
  expect (tokens == again) "tokenization must be deterministic"
  for token in tokens do
    expect token.span.isWellFormed "every token span must be well-formed"

  -- NodeId is path-stable, 128-bit hex, and module/program sensitive.
  let nodes := Examples.counter.enumerateNodes
  expect (nodes.size ≥ 5) "Counter must enumerate structural nodes"
  for record in nodes do
    expect record.nodeId.isWellFormed s!"NodeId malformed at {record.path}"
    expect record.span.isWellFormed s!"span malformed at {record.path}"
    let recomputed := NodeId.ofPath "ProofForgeV2.Examples" "Counter" record.path
    expect (recomputed == record.nodeId)
      s!"NodeId must recompute from module/program/path at {record.path}"
  let againNodes := Examples.counter.enumerateNodes
  expect (nodes.map (·.nodeId) == againNodes.map (·.nodeId))
    "NodeId inventory must be stable across runs"
  let foreign := NodeId.ofPath "Other.Module" "Counter" "entry/increment"
  let localId := NodeId.ofPath "ProofForgeV2.Examples" "Counter" "entry/increment"
  expect (foreign != localId) "module path must participate in NodeId"
  match Program.validateLimits Examples.counter with
  | .ok () => pure ()
  | .error error => throw <| IO.userError error.render

  -- Limit negatives drive the shipped validateLimits entry point.
  let tight : Limits := { maxNodes := 1, maxNesting := 256, maxSourceBytes := 16 * 1024 * 1024, maxLoopBound := 4096 }
  expectErrorCode (Program.validateLimits Examples.counter tight) "PF-BOUND-001"
    "node count over limit must fail closed"
  let shallow : Limits := { maxNodes := 100000, maxNesting := 1, maxSourceBytes := 16 * 1024 * 1024, maxLoopBound := 4096 }
  -- Counter nesting is small; force failure via a deep expression tree program.
  let deepExpr :=
    (List.range 5).foldl (fun acc _ => Expr.checkedAdd acc (.literal 1)) (Expr.literal 0)
  let deepProgram := Program.build "Deep" #[
    .entry {
      name := "run", params := #[], result := .u64, mode := .view,
      body := #[.returnValue deepExpr]
    }
  ]
  expect (deepProgram.maxNesting > 1) "deep expression must increase nesting"
  expectErrorCode (Program.validateLimits deepProgram shallow) "PF-BOUND-001"
    "nesting over limit must fail closed"

  -- Absolute/synthetic span independence: NodeId ignores span fields.
  let withSpan := Examples.counter.enumerateNodes {
    byteStart := 10, byteEnd := 20, line := 3, column := 4
  }
  expect (withSpan.map (·.nodeId) == nodes.map (·.nodeId))
    "NodeId must ignore absolute span coordinates"

  -- Compile path runs validateLimits first (shipped compiler entry).
  match Compiler.compile Examples.counter with
  | .ok _ => pure ()
  | .error error => throw <| IO.userError error.render

end Tests.Language.SourceIdentity
