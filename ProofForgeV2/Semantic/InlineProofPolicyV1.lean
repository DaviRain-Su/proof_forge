import ProofForgeV2.Core.Common
import ProofForgeV2.Core.Canonical

/-
  ProofForgeV2.Semantic.InlineProofPolicyV1 — fixed compiler-owned trust policy
  identity for inline / Environment theorem audit.

  Independent of CLI, Loader, ProgramElaboration, Wire, and ProofBundle loading.
  Canonical payload and digest match SPEC-SEM-001
  `proof-forge.proof-trust-policy.v1` (allowed base axioms only
  Classical.choice / Quot.sound / propext; all capability flags false).

  This module is pure data/identity only: no Environment inspection, no
  `.olean` reads, no axiom addition, no sorry/native_decide.
-/

namespace ProofForgeV2.Semantic.InlineProofPolicyV1

open ProofForgeV2.Core.Common

/-- Wire schema / identity domain for the fixed trust policy. -/
def inlineProofPolicySchemaV1 : String := "proof-forge.proof-trust-policy.v1"

/-- Explicit policy version component (schema already embeds `.v1`). -/
def inlineProofPolicyVersionV1 : String := "1"

/-- Allowed base axiom names as exact UTF-8 strings (SPEC order). -/
def allowedBaseAxiomStringsV1 : Array String :=
  #["Classical.choice", "Quot.sound", "propext"]

/-- Canonical JCS payload. Callers cannot weaken flags or extend axioms. -/
def inlineProofPolicyPayloadV1 : PfJson :=
  .object #[
    ("allowArbitraryTermElaboration", .bool false),
    ("allowBundleAxioms", .bool false),
    ("allowEnvironmentExtensions", .bool false),
    ("allowExtern", .bool false),
    ("allowImplementedBy", .bool false),
    ("allowInitializers", .bool false),
    ("allowNativeArtifacts", .bool false),
    ("allowPartial", .bool false),
    ("allowSyntaxOrElaborators", .bool false),
    ("allowUnsafe", .bool false),
    ("allowedBaseAxioms", .array (allowedBaseAxiomStringsV1.map PfJson.string)),
    ("schema", .string inlineProofPolicySchemaV1)
  ]

/-- Closed policy construction errors. -/
inductive InlineProofPolicyErrorV1 where
  | internal (detail : String)
  deriving BEq, Repr

private def err (e : InlineProofPolicyErrorV1) : Except InlineProofPolicyErrorV1 α :=
  .error e

/-- Independently recomputed fixed trust-policy digest. -/
def inlineProofPolicyDigestV1 : Except InlineProofPolicyErrorV1 Digest := do
  let canonical ← match renderPfJcs inlineProofPolicyPayloadV1 with
    | .ok value => pure value
    | .error e => err (.internal s!"trust-policy PF-JCS: {e}")
  match domainSeparatedSha256 inlineProofPolicySchemaV1 canonical.toUTF8 with
  | .ok digest => pure digest
  | .error e => err (.internal s!"trust-policy digest: {e}")

/-- Frozen policy view for auditors / reports. -/
structure InlineProofPolicyV1 where
  private mk ::
    schema : String
    version : String
    allowedBaseAxioms : Array String
    allowBundleAxioms : Bool
    allowUnsafe : Bool
    allowPartial : Bool
    allowExtern : Bool
    allowImplementedBy : Bool
    allowInitializers : Bool
    allowEnvironmentExtensions : Bool
    allowSyntaxOrElaborators : Bool
    allowNativeArtifacts : Bool
    allowArbitraryTermElaboration : Bool
    digest : Digest

/-- Sole mint of the fixed policy carrier. -/
def mintInlineProofPolicyV1 : Except InlineProofPolicyErrorV1 InlineProofPolicyV1 := do
  let digest ← inlineProofPolicyDigestV1
  pure {
    schema := inlineProofPolicySchemaV1
    version := inlineProofPolicyVersionV1
    allowedBaseAxioms := allowedBaseAxiomStringsV1
    allowBundleAxioms := false
    allowUnsafe := false
    allowPartial := false
    allowExtern := false
    allowImplementedBy := false
    allowInitializers := false
    allowEnvironmentExtensions := false
    allowSyntaxOrElaborators := false
    allowNativeArtifacts := false
    allowArbitraryTermElaboration := false
    digest
  }

/-- Exact string membership in the allowed-base-axiom table. -/
def isAllowedBaseAxiomStringV1 (name : String) : Bool :=
  allowedBaseAxiomStringsV1.any (· == name)

end ProofForgeV2.Semantic.InlineProofPolicyV1
