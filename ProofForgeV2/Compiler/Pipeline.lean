import ProofForgeV2.Core.SemanticIR
import ProofForgeV2.Core.TypedV1
import ProofForgeV2.Source.ValidatedSourceV1

namespace ProofForgeV2.Compiler

open ProofForgeV2.Core.Common
open ProofForgeV2.Source.ValidatedSourceV1

/-- Compatibility compiler entry for hand-built alpha fixtures. Product source
loading uses `compileValidatedSourceV1`; this function does not participate in
the ProgramV1 frontend path. -/
def compile (source : Source.Program) : CompileResult Semantic.Program := do
  let typed ← Typed.check source
  return Semantic.fromTyped source.sourceHash typed

private def invalid (message : String) : CompileResult α :=
  .error (.invalidProgram message)

private def isLowerHex (c : Char) : Bool :=
  ('0' ≤ c && c ≤ '9') || ('a' ≤ c && c ≤ 'f')

private def semanticSourceHash (source : ValidatedSourceV1) : CompileResult String := do
  let digest ← match sourceHashV1 source with
    | .ok digest => pure digest
    | .error error => invalid error
  let rendered ← match renderDigest digest with
    | .ok rendered => pure rendered
    | .error error => invalid error
  unless rendered.startsWith "sha256:" do
    return ← invalid "validated ProgramV1 source hash must use sha256:"
  let suffix := (rendered.drop 7).toString
  unless suffix.length == 64 && suffix.all isLowerHex do
    return ← invalid
      "validated ProgramV1 source hash must contain 64 lowercase hex characters"
  pure suffix

/-- Production target-neutral compiler boundary. ProgramV1 is checked directly
into Typed IR; no legacy `Source.Program` value or fallback exists on this path. -/
def compileValidatedSourceV1 (source : ValidatedSourceV1) : CompileResult Semantic.Program := do
  let typed ← Typed.checkV1 source
  let sourceHash ← semanticSourceHash source
  pure (Semantic.fromTyped sourceHash typed)

end ProofForgeV2.Compiler
