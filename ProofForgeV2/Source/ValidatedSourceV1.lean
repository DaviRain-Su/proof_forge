import ProofForgeV2.Core.Common
import ProofForgeV2.Source.AstCanonicalRootV1
import ProofForgeV2.Source.AstProgramV1
import ProofForgeV2.Source.AstProgramValidateV1
import ProofForgeV2.Source.QualifiedNameV1

namespace ProofForgeV2.Source.ValidatedSourceV1

open ProofForgeV2.Core.Common
open ProofForgeV2.Source.AstCanonicalRootV1
open ProofForgeV2.Source.AstProgramV1
open ProofForgeV2.Source.AstProgramValidateV1
open ProofForgeV2.Source.QualifiedNameV1

/-- A source unit that passed canonical-root and declaration-set validation. -/
structure ValidatedSourceV1 where
  private mk ::
  moduleName : SourceQualifiedNameV1
  programIdentity : SourceQualifiedNameV1
  program : ProgramV1

/-- Exact source fields captured by the `program` elaborator before validation
    evidence is minted. This carrier is deliberately not `ValidatedSourceV1`:
    consumers must enter through the production validator below. -/
structure ElaboratedSourceV1 where
  moduleName : SourceQualifiedNameV1
  programIdentity : SourceQualifiedNameV1
  program : ProgramV1

def validateSourceV1
    (moduleName programIdentity : SourceQualifiedNameV1)
    (program : ProgramV1) : Except String ValidatedSourceV1 := do
  let _ ← canonicalSourceAstBytesV1 moduleName programIdentity program
  validateProgramDeclSetV1 program
  pure ⟨moduleName, programIdentity, program⟩

def canonicalValidatedSourceAstBytesV1
    (source : ValidatedSourceV1) : Except String ByteArray :=
  canonicalSourceAstBytesV1 source.moduleName source.programIdentity source.program

/-- Validate elaborator-captured fields with the sole production source
    validator, then require its canonical encoding to equal the actual export
    payload. Missing, invalid, or drifted input fails closed. -/
def validateElaboratedSourceAgainstCanonicalBytesV1
    (source : ElaboratedSourceV1) (bytes : ByteArray) :
    Except String ValidatedSourceV1 := do
  let validated ←
    validateSourceV1 source.moduleName source.programIdentity source.program
  let actual ← canonicalValidatedSourceAstBytesV1 validated
  if actual == bytes then
    pure validated
  else
    .error "elaborated source canonical bytes do not match program export"

private theorem byteArray_eq_of_beq_eq_true
    {left right : ByteArray} (h : (left == right) = true) : left = right := by
  cases left with
  | mk leftData =>
    cases right with
    | mk rightData =>
      apply ByteArray.ext
      change (leftData == rightData) = true at h
      exact beq_iff_eq.mp h

private theorem validateSourceV1_fields
    (moduleName programIdentity : SourceQualifiedNameV1)
    (program : ProgramV1) (validated : ValidatedSourceV1)
    (hvalidate :
      validateSourceV1 moduleName programIdentity program = .ok validated) :
    validated.moduleName = moduleName ∧
      validated.programIdentity = programIdentity ∧
      validated.program = program ∧
      validateProgramDeclSetV1 validated.program = .ok () := by
  unfold validateSourceV1 at hvalidate
  cases hcanonical :
      canonicalSourceAstBytesV1 moduleName programIdentity program with
  | error error =>
      simp only [hcanonical, Bind.bind, Except.bind] at hvalidate
      cases hvalidate
  | ok canonicalBytes =>
      cases hdeclSet : validateProgramDeclSetV1 program with
      | error error =>
          simp only [hcanonical, hdeclSet, Bind.bind, Except.bind] at hvalidate
          cases hvalidate
      | ok value =>
          cases value
          simp only [hcanonical, hdeclSet, Bind.bind, Except.bind,
            Pure.pure, Except.pure, Except.ok.injEq]
            at hvalidate
          subst validated
          exact ⟨rfl, rfl, rfl, hdeclSet⟩

/-- Soundness boundary for the production validator/encoder join. A successful
    result is the captured AST, passed production declaration validation, and
    canonically encodes to the exact supplied export payload. -/
theorem validateElaboratedSourceAgainstCanonicalBytesV1_sound
    (source : ElaboratedSourceV1) (bytes : ByteArray)
    (validated : ValidatedSourceV1)
    (hvalidate :
      validateElaboratedSourceAgainstCanonicalBytesV1 source bytes =
        .ok validated) :
    validated.moduleName = source.moduleName ∧
      validated.programIdentity = source.programIdentity ∧
      validated.program = source.program ∧
      validateProgramDeclSetV1 validated.program = .ok () ∧
      canonicalValidatedSourceAstBytesV1 validated = .ok bytes := by
  unfold validateElaboratedSourceAgainstCanonicalBytesV1 at hvalidate
  cases hsource :
      validateSourceV1 source.moduleName source.programIdentity source.program with
  | error error =>
      simp only [hsource, Bind.bind, Except.bind] at hvalidate
      cases hvalidate
  | ok candidate =>
      cases hcanonical : canonicalValidatedSourceAstBytesV1 candidate with
      | error error =>
          simp only [hsource, hcanonical, Bind.bind, Except.bind] at hvalidate
          cases hvalidate
      | ok actual =>
          cases hbytes : actual == bytes with
          | false =>
              simp only [hsource, hcanonical, hbytes, Bind.bind, Except.bind,
                Bool.false_eq_true, ↓reduceIte] at hvalidate
              cases hvalidate
          | true =>
              simp only [hsource, hcanonical, hbytes, Bind.bind, Except.bind,
                Pure.pure, Except.pure, ↓reduceIte, Except.ok.injEq] at hvalidate
              subst validated
              have hfields := validateSourceV1_fields
                source.moduleName source.programIdentity source.program
                candidate hsource
              have heq : actual = bytes :=
                byteArray_eq_of_beq_eq_true hbytes
              subst actual
              exact ⟨hfields.1, hfields.2.1, hfields.2.2.1,
                hfields.2.2.2, hcanonical⟩

/-- Proof-carrying result of binding an elaborator-captured source to one exact
    canonical export payload through the production validator and encoder. -/
structure CanonicalSourceBindingV1
    (elaborated : ElaboratedSourceV1) (bytes : ByteArray) where
  validated : ValidatedSourceV1
  moduleName_eq : validated.moduleName = elaborated.moduleName
  programIdentity_eq : validated.programIdentity = elaborated.programIdentity
  program_eq : validated.program = elaborated.program
  declSet_valid : validateProgramDeclSetV1 validated.program = .ok ()
  canonicalBytes_eq : canonicalValidatedSourceAstBytesV1 validated = .ok bytes

/-- Mint a proof-carrying canonical source binding only after the production
    validator/encoder join succeeds. The failure diagnostic is preserved. -/
def bindElaboratedSourceToCanonicalBytesV1
    (elaborated : ElaboratedSourceV1) (bytes : ByteArray) :
    Except String (CanonicalSourceBindingV1 elaborated bytes) :=
  match hvalidate :
      validateElaboratedSourceAgainstCanonicalBytesV1 elaborated bytes with
  | .error error => .error error
  | .ok validated =>
      let sound :=
        validateElaboratedSourceAgainstCanonicalBytesV1_sound
          elaborated bytes validated hvalidate
      .ok {
        validated
        moduleName_eq := sound.1
        programIdentity_eq := sound.2.1
        program_eq := sound.2.2.1
        declSet_valid := sound.2.2.2.1
        canonicalBytes_eq := sound.2.2.2.2
      }

def sourceHashV1 (source : ValidatedSourceV1) : Except String Digest := do
  let bytes ← canonicalValidatedSourceAstBytesV1 source
  domainSeparatedSha256 "pf.source.v1" bytes

end ProofForgeV2.Source.ValidatedSourceV1
