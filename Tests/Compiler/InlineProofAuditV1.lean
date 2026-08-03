import Lean
import ProofForgeV2.Compiler.InlineProofAuditV1
import ProofForgeV2.Semantic.InlineProofPolicyV1
import ProofForgeV2.Core.Common

/-
  Focused engineering tests for InlineProofPolicyV1 + InlineProofAuditV1.

  Trusted test command constructs Environment declarations in this module, then
  audits them via structured Environment APIs (no `#print axioms` text, no
  user `.olean` reads, no CLI/Loader).
-/

open Lean
open Lean.Elab.Command
open ProofForgeV2.Compiler.InlineProofAuditV1
open ProofForgeV2.Semantic.InlineProofPolicyV1
open ProofForgeV2.Core.Common

namespace Tests.Compiler.InlineProofAuditV1

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def expectOk
    (label : String)
    (result : Except InlineProofAuditErrorV1 InlineProofAuditReportV1) : IO Unit :=
  match result with
  | .ok _ => pure ()
  | .error e => throw <| IO.userError s!"{label}: unexpectedly rejected: {repr e}"

private def expectErr
    (label : String)
    (result : Except InlineProofAuditErrorV1 InlineProofAuditReportV1)
    (pred : InlineProofAuditErrorV1 → Bool) : IO Unit :=
  match result with
  | .ok _ => throw <| IO.userError s!"{label}: unexpectedly accepted"
  | .error e =>
      unless pred e do
        throw <| IO.userError s!"{label}: wrong error: {repr e}"

private def typeOf! (env : Environment) (name : Name) : IO Expr :=
  match env.find? name with
  | some info => pure info.type
  | none => throw <| IO.userError s!"missing fixture type: {name}"

/-- Product-style expected row: theorem type is the named proposition itself
    (`mkConst name` of the theorem's type constant when it is a named alias),
    not a declaration's `info.type` when that declaration is an alias of type
    `Prop`. For ordinary `True` theorems the type expression is `True`. -/
private def expectedOf (env : Environment) (name : Name) : IO ExpectedInlineTheoremV1 := do
  pure { name, expectedType := (← typeOf! env name) }

/-! ### Trusted Environment fixtures -/

theorem audit_good_true : True := trivial

theorem audit_uses_choice (h : Nonempty True) : True := Classical.choice h

axiom audit_user_axiom : True

theorem audit_uses_user_axiom : True := audit_user_axiom

-- Direct sorryAx application (not `by sorry`) so the declaration value is
-- inspectable without synthetic-sorry command evaluation side channels.
theorem audit_sorry_true : True := sorryAx True false

def audit_impl_target : Nat := 0

@[implemented_by audit_impl_target]
def audit_impl_surface : Nat := 0

theorem audit_uses_implemented_by : audit_impl_surface = audit_impl_surface := rfl

@[extern "proof_forge_audit_extern_sentinel"]
opaque audit_extern_surface : Nat

theorem audit_uses_extern : audit_extern_surface = audit_extern_surface := rfl

def audit_init_fn : IO Nat := pure 0

@[init audit_init_fn]
opaque audit_init_surface : Nat

theorem audit_uses_initializer : audit_init_surface = audit_init_surface := rfl

unsafe def audit_unsafe_true : True := trivial

theorem audit_type_nat : True := trivial

/-- Product Prop-alias shape: `abbrev Alias : Prop := True`. Expected audit type
    must be `mkConst ``audit_prop_alias`, never the alias decl's `info.type`
    (`Prop`). -/
abbrev audit_prop_alias : Prop := True

theorem audit_via_alias : audit_prop_alias := trivial

/-- Opaque root with a value — product audit must reject (theorem roots only). -/
opaque audit_opaque_root : True := trivial

private def trueType : Expr := mkConst ``True

private def runPolicyPins : IO Unit := do
  let policy ← match mintInlineProofPolicyV1 with
    | .ok p => pure p
    | .error e => throw <| IO.userError s!"policy mint: {repr e}"
  expect (policy.schema == inlineProofPolicySchemaV1) "policy schema"
  expect (policy.version == inlineProofPolicyVersionV1) "policy version"
  expect (policy.allowedBaseAxioms == allowedBaseAxiomStringsV1) "allowed axioms"
  expect (!policy.allowBundleAxioms) "allowBundleAxioms false"
  expect (!policy.allowUnsafe) "allowUnsafe false"
  expect (!policy.allowPartial) "allowPartial false"
  expect (!policy.allowExtern) "allowExtern false"
  expect (!policy.allowImplementedBy) "allowImplementedBy false"
  expect (!policy.allowInitializers) "allowInitializers false"
  expect (!policy.allowEnvironmentExtensions) "allowEnvironmentExtensions false"
  expect (!policy.allowSyntaxOrElaborators) "allowSyntaxOrElaborators false"
  expect (!policy.allowNativeArtifacts) "allowNativeArtifacts false"
  expect (!policy.allowArbitraryTermElaboration) "allowArbitraryTermElaboration false"
  expect (isAllowedBaseAxiomStringV1 "Classical.choice") "choice allowed"
  expect (isAllowedBaseAxiomStringV1 "Quot.sound") "quot allowed"
  expect (isAllowedBaseAxiomStringV1 "propext") "propext allowed"
  expect (!isAllowedBaseAxiomStringV1 "sorryAx") "sorryAx rejected by policy table"
  expect (isAllowedBaseAxiomNameV1 ``Classical.choice) "choice name allowed"
  expect (!isAllowedBaseAxiomNameV1 ``sorryAx) "sorryAx name rejected"
  let digest2 ← match inlineProofPolicyDigestV1 with
    | .ok d => pure d
    | .error e => throw <| IO.userError s!"policy digest: {repr e}"
  expect (policy.digest.bytes == digest2.bytes) "policy digest stable"

private def runAuditCases (env : Environment) : IO Unit := do
  expectOk "good_true" <|
    auditExpectedTheoremsV1 env #[← expectedOf env ``audit_good_true]
  expectOk "uses_choice" <|
    auditExpectedTheoremsV1 env #[← expectedOf env ``audit_uses_choice]
  -- Kernel-defeq positive: expected expression is `mkConst <alias>`, matching
  -- product certifier construction (not the alias declaration's type `Prop`).
  expectOk "alias_mkConst" <|
    auditExpectedTheoremsV1 env
      #[{ name := ``audit_via_alias, expectedType := mkConst ``audit_prop_alias }]
  -- Using the alias declaration's `info.type` (`Prop`) must fail defeq against
  -- the theorem's type (`audit_prop_alias`).
  let aliasDeclType ← typeOf! env ``audit_prop_alias
  expect (aliasDeclType.consumeMData == .sort 0) "alias decl type is Prop (sort 0)"
  expectErr "alias_decl_type_not_expected"
    (auditExpectedTheoremsV1 env
      #[{ name := ``audit_via_alias, expectedType := aliasDeclType }])
    fun
      | .typeNotDefEq n => n == ``audit_via_alias
      | _ => false
  expectErr "missing"
    (auditExpectedTheoremsV1 env
      #[{ name := `AuditMissingDoesNotExist, expectedType := trueType }])
    fun
      | .missingDeclaration n => n == `AuditMissingDoesNotExist
      | _ => false
  expectErr "type_mismatch"
    (auditExpectedTheoremsV1 env
      #[{ name := ``audit_type_nat, expectedType := mkConst ``False }])
    fun
      | .typeNotDefEq n => n == ``audit_type_nat
      | _ => false
  expectErr "root_axiom"
    (auditExpectedTheoremsV1 env #[← expectedOf env ``audit_user_axiom])
    fun
      | .kindRejected n _ => n == ``audit_user_axiom
      | _ => false
  expectErr "root_opaque"
    (auditExpectedTheoremsV1 env
      #[{ name := ``audit_opaque_root, expectedType := trueType }])
    fun
      | .kindRejected n _ => n == ``audit_opaque_root
      | _ => false
  expectErr "user_axiom_closure"
    (auditExpectedTheoremsV1 env #[← expectedOf env ``audit_uses_user_axiom])
    fun
      | .forbiddenAxiom owner ax =>
          owner == ``audit_uses_user_axiom && ax == ``audit_user_axiom
      | _ => false
  expectErr "sorry"
    (auditExpectedTheoremsV1 env #[← expectedOf env ``audit_sorry_true])
    fun
      | .sorryInDecl n => n == ``audit_sorry_true
      | .forbiddenAxiom _ ax => ax == ``sorryAx
      | _ => false
  expectErr "implemented_by"
    (auditExpectedTheoremsV1 env #[← expectedOf env ``audit_uses_implemented_by])
    fun
      | .forbiddenAttribute n attr =>
          n == ``audit_impl_surface && attr == "implemented_by"
      | _ => false
  expectErr "extern"
    (auditExpectedTheoremsV1 env #[← expectedOf env ``audit_uses_extern])
    fun
      | .forbiddenAttribute n attr =>
          n == ``audit_extern_surface && attr == "extern"
      | _ => false
  expectErr "initializer"
    (auditExpectedTheoremsV1 env #[← expectedOf env ``audit_uses_initializer])
    fun
      | .forbiddenAttribute n attr =>
          n == ``audit_init_surface && attr == "initializer"
      | _ => false
  expectErr "unsafe_root"
    (auditExpectedTheoremsV1 env #[← expectedOf env ``audit_unsafe_true])
    fun
      | .unsafeDecl n => n == ``audit_unsafe_true
      | .kindRejected n _ => n == ``audit_unsafe_true
      | _ => false
  match auditExpectedTheoremsV1 env #[← expectedOf env ``audit_good_true] with
  | .error e => throw <| IO.userError s!"report: {repr e}"
  | .ok report => do
      let policy ← match mintInlineProofPolicyV1 with
        | .ok p => pure p
        | .error e => throw <| IO.userError s!"policy: {repr e}"
      expect (report.policyVersion == inlineProofPolicyVersionV1) "report version"
      expect (report.policyDigest.bytes == policy.digest.bytes) "report digest"
      expect (report.audited == #[``audit_good_true]) "report audited names"

run_cmd do
  let env ← getEnv
  liftIO runPolicyPins
  liftIO (runAuditCases env)

def run : IO Unit := do
  runPolicyPins
  IO.println "Tests.Compiler.InlineProofAuditV1: ok"

end Tests.Compiler.InlineProofAuditV1
