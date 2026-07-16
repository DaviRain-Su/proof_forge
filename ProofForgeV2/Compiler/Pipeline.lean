import ProofForgeV2.Core.SemanticIR

namespace ProofForgeV2.Compiler

/-- The target-neutral compiler boundary. Source requirements are deliberately
ignored: Typed checking resolves names and effects, then Semantic normalization
derives requirements from the checked operations. -/
def compile (source : Source.Program) : CompileResult Semantic.Program := do
  let typed ← Typed.check source
  return Semantic.fromTyped source.sourceHash typed

end ProofForgeV2.Compiler
