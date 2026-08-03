import Lean
import ProofForgeV2.Compiler.InlineProofAuditV1
import ProofForgeV2.Compiler.InlineProofElaborationV1
import ProofForgeV2.Compiler.InlineProofProtocolV1
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Language.ProgramExport
import ProofForgeV2.Language.TheoremInventoryV1
import ProofForgeV2.Semantic.ProofSubjectV1
import ProofForgeV2.Source.OriginJoinV1
import ProofForgeV2.Source.QualifiedNameV1
import ProofForgeV2.Source.ValidatedSourceV1

/-
  ProofForgeV2.Compiler.InlineProofCertifierV1 — pure product-facing inline
  proof certifier (engineering; not formal TST-PROOF-001).

  Inputs are already held in memory from one Loader/product compile path:
    * raw source String
    * ValidatedSourceV1 + OriginInventoryV1 + TheoremInventoryV1
    * CompiledSemanticV1
    * logical ProjectRelativePath + module / program selectors

  Pipeline:
    1. exact `proofSubjectOfCompiledSemanticV1`
    2. invariant source-order ordinals + inventory → protocol obligations
    3. canonical request binding raw source bytes and subject digests
    4. in-process `elaborateInlineProofSourceV1` (no file re-read, no worker)
    5. decode generated `<program>.Proof.subjectProgramV1` literal bytes and
       require exact equality with `CompiledSemanticV1.semanticV1Of.canonicalBytes`
    6. Environment FQN audit of each user theorem against generated Prop alias
    7. only audit success mints private `CertifiedInlineProofV1`

  Security:
    * `mkInlineProofSuccessV1` is not a capability — product accepts only this
      module's private certifier carrier
    * empty proofs return explicit `noProof` (never forged success)
    * failures are closed phase/detail (no message printing, no disk, no spawn)
-/

namespace ProofForgeV2.Compiler.InlineProofCertifierV1

open Lean
open ProofForgeV2.Compiler
open ProofForgeV2.Compiler.InlineProofAuditV1
open ProofForgeV2.Compiler.InlineProofElaborationV1
open ProofForgeV2.Compiler.InlineProofProtocolV1
open ProofForgeV2.Core.Common
open ProofForgeV2.Language.ProgramExport
open ProofForgeV2.Language.TheoremInventoryV1
open ProofForgeV2.Semantic.ProofSubjectV1
open ProofForgeV2.Semantic.WireV1
open ProofForgeV2.Source.NameComponentV1
open ProofForgeV2.Source.OriginJoinV1
open ProofForgeV2.Source.QualifiedNameV1
open ProofForgeV2.Source.ValidatedSourceV1

/-- Closed certifier failure detail (no free-form messages on the product surface). -/
inductive InlineProofCertifierDetailV1 where
  | subjectBuild
  | obligationMap
  | requestBuild
  | elaborate
  | subjectBytes
  | missingSubjectDecl
  | missingTheorem
  | missingExpectedType
  | audit
  | successMint
  | internal
  deriving BEq, DecidableEq, Repr, Inhabited

/-- Private product capability. Sole mint is `certifyInlineProofV1` after
    successful Environment audit. Protocol `mkInlineProofSuccessV1` alone cannot
    construct this carrier. -/
structure CertifiedInlineProofV1 where
  private mk ::
  private success_ : InlineProofSuccessV1
  private audit_ : InlineProofAuditReportV1

namespace CertifiedInlineProofV1

def success (c : CertifiedInlineProofV1) : InlineProofSuccessV1 :=
  c.success_

def audit (c : CertifiedInlineProofV1) : InlineProofAuditReportV1 :=
  c.audit_

def requestDigest (c : CertifiedInlineProofV1) : Digest :=
  InlineProofSuccessV1.requestDigest c.success_

def theoremCount (c : CertifiedInlineProofV1) : UInt32 :=
  InlineProofSuccessV1.theoremCount c.success_

def theoremSetDigest (c : CertifiedInlineProofV1) : Digest :=
  InlineProofSuccessV1.theoremSetDigest c.success_

def proofCertificationDigest (c : CertifiedInlineProofV1) : Digest :=
  InlineProofSuccessV1.proofCertificationDigest c.success_

def policyDigest (c : CertifiedInlineProofV1) : Digest :=
  InlineProofAuditReportV1.policyDigest c.audit_

def audited (c : CertifiedInlineProofV1) : Array Name :=
  InlineProofAuditReportV1.audited c.audit_

end CertifiedInlineProofV1

/-- Product certifier outcome. `noProof` is an explicit skip, not success. -/
inductive InlineProofCertifierOutcomeV1 where
  | certified (value : CertifiedInlineProofV1)
  | noProof
  | failed (phase : InlineProofFailurePhaseV1) (detail : InlineProofCertifierDetailV1)

instance : Repr InlineProofCertifierOutcomeV1 where
  reprPrec
    | .certified _, _ => "InlineProofCertifierOutcomeV1.certified ⟨…⟩"
    | .noProof, _ => "InlineProofCertifierOutcomeV1.noProof"
    | .failed phase detail, prec =>
        Repr.addAppParen
          (Std.Format.group <|
            Std.Format.nest 2 <|
              "InlineProofCertifierOutcomeV1.failed" ++
                Std.Format.line ++ repr phase ++
                Std.Format.line ++ repr detail)
          prec

private def fail
    (phase : InlineProofFailurePhaseV1) (detail : InlineProofCertifierDetailV1) :
    InlineProofCertifierOutcomeV1 :=
  .failed phase detail

private def componentsToLeanName (components : Array String) : Name :=
  components.foldl (init := Name.anonymous) fun acc part => Name.str acc part

private def leanNameFromSelector (selector : String) : Name :=
  if selector.isEmpty then
    Name.anonymous
  else
    componentsToLeanName (selector.splitOn ".").toArray

/-- Drop the final program-name component of `programIdentity` to recover the
    ambient namespace under which adjacent theorems are elaborated. -/
private def programAmbientComponentsV1 (source : ValidatedSourceV1) :
    Except InlineProofCertifierDetailV1 (Array String) := do
  let comps := (NonEmptyArray.toArray source.programIdentity.components).map (·.raw)
  if comps.size < 2 then
    return ← .error .internal
  pure (comps.extract 0 (comps.size - 1))

/-- Source-order invariant names (declaration order = ordinal). -/
private def invariantNamesSourceOrderV1 (source : ValidatedSourceV1) : Array String :=
  Id.run do
    let mut names : Array String := #[]
    for item in source.program.items do
      match item with
      | .invariant d => names := names.push d.name.raw
      | _ => pure ()
    pure names

/-- Treat theorem inventory as untrusted: recompute the sole expected binding
    table from `source.program.items` via `expectedTheoremsFromProgramV1` and
    require exact count/order/name/invariant/typeComponents bijection. Rejects
    forged empty, partial, extra, reordered, or name-swapped inventories. -/
private def validateTheoremInventoryBijectionV1
    (source : ValidatedSourceV1) (inventory : TheoremInventoryV1) :
    Except InlineProofCertifierDetailV1 (Array ExpectedTheoremV1) := do
  let programName := source.program.name.raw
  let expected ← match expectedTheoremsFromProgramV1 programName source with
    | .ok value => pure value
    | .error _ => return ← .error .obligationMap
  let bindings := theoremInventoryBindingsV1 inventory
  unless bindings.size == expected.size do
    return ← .error .obligationMap
  for i in [:expected.size] do
    let exp := expected[i]!
    let got := bindings[i]!
    unless got.theoremComponents == exp.theoremComponents &&
        got.invariantName == exp.invariantName &&
        got.typeComponents == exp.typeComponents do
      return ← .error .obligationMap
  pure expected

/-- Map validated inventory bindings onto protocol obligations using invariant
    declaration source-order ordinals (not proof-item order). Caller must have
    already enforced inventory↔program bijection. -/
private def obligationsFromInventoryV1
    (source : ValidatedSourceV1) (inventory : TheoremInventoryV1) :
    Except InlineProofCertifierDetailV1 (Array InlineProofObligationV1) := do
  let invNames := invariantNamesSourceOrderV1 source
  let bindings := theoremInventoryBindingsV1 inventory
  let mut obligations : Array InlineProofObligationV1 := Array.mkEmpty bindings.size
  let mut seenOrdinals : Array UInt32 := #[]
  for binding in bindings do
    let ordinalNat ← match invNames.idxOf? binding.invariantName with
      | some idx => pure idx
      | none => return ← .error .obligationMap
    unless ordinalNat ≤ UInt32.size - 1 do
      return ← .error .obligationMap
    let ordinal := UInt32.ofNat ordinalNat
    if seenOrdinals.any (· == ordinal) then
      return ← .error .obligationMap
    seenOrdinals := seenOrdinals.push ordinal
    let theoremName ← match parseQualifiedName binding.theoremComponents with
      | .ok qn => pure qn
      | .error _ => return ← .error .obligationMap
    let obligation ← match mkInlineProofObligationV1
        binding.invariantName ordinal theoremName binding.invariantName with
      | .ok value => pure value
      | .error _ => return ← .error .obligationMap
    obligations := obligations.push obligation
  pure obligations

/-- Conservative presence/shape gate for generated Prop aliases
    (`abbrev Inv : Prop := InvariantTheoremV1 …`). Accepts only safe, non-extern
    definitions whose type is exactly `Prop`. Does **not** use `info.type` as the
    expected proposition (that is only `Prop`); the expected expression is
    always `mkConst typeName`. -/
private def requireGeneratedPropAliasV1
    (env : Environment) (typeName : Name) :
    Except InlineProofCertifierDetailV1 Unit := do
  match env.find? typeName with
  | none => .error .missingExpectedType
  | some (.defnInfo info) =>
      -- `Prop` elaborates as `Expr.sort 0` (not `mkConst \`Prop`).
      unless info.type.consumeMData == .sort 0 do
        return ← .error .missingExpectedType
      match info.safety with
      | .safe => pure ()
      | _ => return ← .error .missingExpectedType
      unless (Lean.Compiler.getImplementedBy? env typeName).isNone do
        return ← .error .missingExpectedType
      unless (Lean.getExternAttrData? env typeName).isNone do
        return ← .error .missingExpectedType
      pure ()
  | some _ => .error .missingExpectedType

/-- Build Environment expected-theorem rows: FQN =
    ambient program namespace + inventory theorem components; expected type is
    `mkConst <programIdentity>.Proof.<inv>` (the generated Prop alias name),
    never the alias declaration's `info.type` (`Prop`). -/
private def expectedTheoremsForAuditV1
    (env : Environment)
    (source : ValidatedSourceV1)
    (inventory : TheoremInventoryV1) :
    Except InlineProofCertifierDetailV1 (Array ExpectedInlineTheoremV1) := do
  let ambient ← programAmbientComponentsV1 source
  let programComps :=
    (NonEmptyArray.toArray source.programIdentity.components).map (·.raw)
  let bindings := theoremInventoryBindingsV1 inventory
  let mut expected : Array ExpectedInlineTheoremV1 := Array.mkEmpty bindings.size
  for binding in bindings do
    let thmName := componentsToLeanName (ambient ++ binding.theoremComponents)
    unless env.contains thmName do
      return ← .error .missingTheorem
    let typeName :=
      componentsToLeanName (programComps ++ #["Proof", binding.invariantName])
    requireGeneratedPropAliasV1 env typeName
    -- Expected proposition is the alias constant itself, not its type `Prop`.
    expected := expected.push { name := thmName, expectedType := mkConst typeName }
  pure expected

/-- Decode generated `<program>.Proof.subjectProgramV1` definition value to
    exact canonical semantic bytes. Accepts only
    `SemanticProgramV1.mk <transparent ByteArray expr>`; never evaluates
    arbitrary terms. -/
private def decodeGeneratedSubjectBytesV1
    (env : Environment) (decl : Name) :
    Except InlineProofCertifierDetailV1 ByteArray := do
  match env.find? decl with
  | none => .error .missingSubjectDecl
  | some (.defnInfo info) =>
      unless info.type.consumeMData == mkConst ``SemanticProgramV1 do
        return ← .error .subjectBytes
      match info.safety with
      | .safe => pure ()
      | _ => return ← .error .subjectBytes
      unless (Lean.Compiler.getImplementedBy? env decl).isNone do
        return ← .error .subjectBytes
      unless (Lean.getExternAttrData? env decl).isNone do
        return ← .error .subjectBytes
      match checkExportRawNodeBoundV1 info.value with
      | .error _ => return ← .error .subjectBytes
      | .ok () => pure ()
      if env.hasUnsafe info.value then
        return ← .error .subjectBytes
      let value := info.value.consumeMData
      let bytesExpr? : Option Expr :=
        match value with
        | .app fn arg =>
            match fn.consumeMData with
            | .const name _ =>
                if name == ``SemanticProgramV1.mk then some arg.consumeMData
                else none
            | .app fn2 _ =>
                -- Possible packing with type args; take the final app arg.
                match fn2.getAppFn with
                | .const name _ =>
                    if name == ``SemanticProgramV1.mk then some arg.consumeMData
                    else none
                | _ => none
            | _ => none
        | _ => none
      match bytesExpr? with
      | none =>
          -- Fall back: full getAppFn view.
          match value.getAppFn with
          | .const name _ =>
              if name == ``SemanticProgramV1.mk then
                match value.getAppArgs.back? with
                | some bytesExpr =>
                    match decodeBoundedByteArrayExprV1 bytesExpr with
                    | .ok bytes => pure bytes
                    | .error _ => .error .subjectBytes
                | none => .error .subjectBytes
              else
                .error .subjectBytes
          | _ => .error .subjectBytes
      | some bytesExpr =>
          match decodeBoundedByteArrayExprV1 bytesExpr with
          | .ok bytes => pure bytes
          | .error _ => .error .subjectBytes
  | some _ => .error .missingSubjectDecl

/-- Core product certifier. Never opens files, never spawns a worker, never
    prints diagnostics. -/
unsafe def certifyInlineProofV1
    (rawSource : String)
    (source : ValidatedSourceV1)
    (originInventory : OriginInventoryV1)
    (theoremInventory : TheoremInventoryV1)
    (compiled : CompiledSemanticV1)
    (sourcePath : ProjectRelativePath)
    (moduleSelector : String)
    (programSelector : Option String) :
    IO InlineProofCertifierOutcomeV1 := do
  -- 0) Inventory is untrusted: recompute expected bindings from source items
  --    and require exact bijection before any noProof / certification path.
  let expectedBindings ← match
      validateTheoremInventoryBijectionV1 source theoremInventory with
    | .ok value => pure value
    | .error detail => return fail .obligation detail
  -- Empty expected proof surface: explicit skip (never forged success).
  if expectedBindings.isEmpty then
    return .noProof

  -- 1) Exact production proof subject from retained compile carrier.
  let subject ← match proofSubjectOfCompiledSemanticV1
      source originInventory compiled with
    | .ok value => pure value
    | .error _ => return fail .subject .subjectBuild

  -- 2) Inventory → ordered protocol obligations (invariant source-order ordinals).
  let obligations ← match obligationsFromInventoryV1 source theoremInventory with
    | .ok value => pure value
    | .error detail => return fail .obligation detail

  -- 3) Canonical request binds raw source bytes + subject digests.
  let sourceBytes := rawSource.toUTF8
  let request ← match mkInlineProofRequestV1
      sourcePath moduleSelector programSelector sourceBytes
      subject.sourceHash subject.semanticHash subject.semanticProvenanceDigest
      obligations with
    | .ok value => pure value
    | .error _ => return fail .request .requestBuild

  -- 4) In-process elaboration of the same held raw source (no re-read).
  let fileName ← match renderProjectRelativePath sourcePath with
    | .ok value => pure value
    | .error _ => pure "<inline-proof>"
  let mainModule := leanNameFromSelector moduleSelector
  let elabResult ← elaborateInlineProofSourceV1 rawSource fileName mainModule
  let elabEnv ← match elabResult with
    | .ok value => pure value
    | .error _ => return fail .certification .elaborate
  let env := InlineProofElabEnvV1.environment elabEnv

  -- 5) Generated subjectProgramV1 literal bytes == compiled semantic bytes.
  let programComps :=
    (NonEmptyArray.toArray source.programIdentity.components).map (·.raw)
  let subjectDecl :=
    componentsToLeanName (programComps ++ #["Proof", "subjectProgramV1"])
  let generatedBytes ← match decodeGeneratedSubjectBytesV1 env subjectDecl with
    | .ok bytes => pure bytes
    | .error detail => return fail .subject detail
  let expectedBytes :=
    (CompiledSemanticV1.semanticV1Of compiled).canonicalBytes
  unless generatedBytes == expectedBytes do
    return fail .subject .subjectBytes

  -- 6) Audit each user theorem against generated Prop aliases.
  let expected ← match expectedTheoremsForAuditV1 env source theoremInventory with
    | .ok value => pure value
    | .error detail => return fail .certification detail
  let auditReport ← match auditExpectedTheoremsV1 env expected with
    | .ok report => pure report
    | .error _ => return fail .certification .audit

  -- 7) Only audit success mints the private certifier carrier.
  let success ← match mkInlineProofSuccessV1 request with
    | .ok value => pure value
    | .error _ => return fail .certification .successMint
  pure (.certified ⟨success, auditReport⟩)

end ProofForgeV2.Compiler.InlineProofCertifierV1
