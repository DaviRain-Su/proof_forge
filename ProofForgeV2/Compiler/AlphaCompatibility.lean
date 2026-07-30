/-
  Legacy alpha compiler compatibility for hand-built `Source.Program` fixtures.

  This module is deliberately separate from `Compiler.Pipeline`: the ProgramV1
  product compiler must not import or execute alpha Typed/Semantic lowering.
  It remains non-product characterization only until the legacy alpha test
  surface is retired.
-/
import ProofForgeV2.Core.DiagnosticBundleV1
import ProofForgeV2.Core.SemanticIR
import ProofForgeV2.Core.TypedV1

namespace ProofForgeV2.Compiler.AlphaCompatibility

/-- Compatibility compiler entry for hand-built alpha fixtures. Product source
    loading uses `compileProgramProductV1` from `Compiler.Pipeline`; this
    function does not participate in the ProgramV1 frontend path. -/
def compile (source : Source.Program) : CompileResult Semantic.Program := do
  let typed ← Typed.check source
  return Semantic.fromTyped source.sourceHash typed

end ProofForgeV2.Compiler.AlphaCompatibility
