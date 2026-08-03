import Lean
import ProofForgeV2.Core.Common
import ProofForgeV2.Semantic.InlineProofPolicyV1

/-
  ProofForgeV2.Compiler.InlineProofAuditV1 — structured Environment theorem audit
  against the fixed InlineProofPolicyV1.

  Given a Lean Environment and expected theorem names/types:
    * declaration must exist
    * type must be kernel-defeq to the expected type
    * declaration must not be unsafe / partial
    * value must exist and must not contain sorryAx
    * recursive type/value constant dependency closure must not contain
      user axioms, sorryAx, implemented_by, extern, or initializer attrs

  Allowed base axioms (only): Classical.choice, Quot.sound, propext.

  Explicit non-goals:
    * `#print axioms` text parsing
    * reading user `.olean` files
    * adding axiom / sorry / native_decide
    * CLI / Loader / ProgramElaboration / Wire product paths
-/

namespace ProofForgeV2.Compiler.InlineProofAuditV1

open Lean
open ProofForgeV2.Core.Common
open ProofForgeV2.Semantic.InlineProofPolicyV1

/-- Expected theorem identity for audit. -/
structure ExpectedInlineTheoremV1 where
  name : Name
  expectedType : Expr
  deriving Inhabited

/-- Closed structured audit failures. -/
inductive InlineProofAuditErrorV1 where
  | policy (detail : String)
  | missingDeclaration (name : Name)
  | kindRejected (name : Name) (detail : String)
  | typeNotDefEq (name : Name)
  | unsafeDecl (name : Name)
  | partialDecl (name : Name)
  | missingValue (name : Name)
  | sorryInDecl (name : Name)
  | forbiddenAxiom (owner : Name) (axiomName : Name)
  | forbiddenAttribute (name : Name) (attrName : String)
  | kernelFailure (detail : String)
  | internal (detail : String)
  deriving BEq, Repr

/-- Successful audit summary (policy identity + audited root names).
    Private construction prevents callers from forging an audit result without
    traversing the Environment through `auditExpectedTheoremsV1`. -/
structure InlineProofAuditReportV1 where
  private mk ::
  private policyDigest_ : Digest
  private policyVersion_ : String
  private audited_ : Array Name
  deriving Repr

namespace InlineProofAuditReportV1

def policyDigest (report : InlineProofAuditReportV1) : Digest :=
  report.policyDigest_

def policyVersion (report : InlineProofAuditReportV1) : String :=
  report.policyVersion_

def audited (report : InlineProofAuditReportV1) : Array Name :=
  report.audited_

end InlineProofAuditReportV1

private def err (e : InlineProofAuditErrorV1) : Except InlineProofAuditErrorV1 α :=
  .error e

/-- Allowed base axioms as Lean names (exact SPEC set). -/
def allowedBaseAxiomNamesV1 : Array Name :=
  #[``Classical.choice, ``Quot.sound, ``propext]

def isAllowedBaseAxiomNameV1 (name : Name) : Bool :=
  allowedBaseAxiomNamesV1.any (· == name)

/-- Fixed trusted package module roots whose imported declarations may carry
    host ABI (`extern` / `implemented_by` / initializer) without failing the
    product audit. User main-module declarations are never trusted this way.

    Membership is by *importing module name* (not declaration name prefix), so
    prelude roots such as `ByteArray.beq` (module `Init.Data.ByteArray`) and
    package constants under `ProofForgeV2.*` are covered without a blanket
    "any imported name" relaxation. -/
def trustedImportedPackageModuleRootsV1 : Array Name :=
  #[`Init, `Lean, `Std, `ProofForgeV2]

/-- True when `name` is an imported constant from a fixed trusted package
    module (Init / Lean / Std / ProofForgeV2). Main-module declarations always
    return false. -/
def isTrustedImportedPackageDeclV1 (env : Environment) (name : Name) : Bool :=
  match env.getModuleIdxFor? name with
  | none => false
  | some idx =>
      let modules := env.header.moduleNames
      if h : idx.toNat < modules.size then
        let modName := modules[idx.toNat]
        trustedImportedPackageModuleRootsV1.any fun root =>
          modName == root || root.isPrefixOf modName
      else
        false

/-- Reject implemented_by / extern / initializer attributes on a constant.

    Imported declarations from the fixed trusted package module roots may keep
    host ABI attributes (ByteArray externs, package native helpers). User
    main-module declarations are always rejected for these attributes. -/
private def rejectForbiddenAttrs
    (env : Environment) (name : Name) :
    Except InlineProofAuditErrorV1 Unit := do
  if isTrustedImportedPackageDeclV1 env name then
    return
  unless (Compiler.getImplementedBy? env name).isNone do
    return ← err (.forbiddenAttribute name "implemented_by")
  unless (getExternAttrData? env name).isNone do
    return ← err (.forbiddenAttribute name "extern")
  if hasInitAttr env name then
    return ← err (.forbiddenAttribute name "initializer")
  pure ()

/-- Product root export kind: theorem only. Opaque roots are rejected even when
    they carry a value; dependency closure may still traverse opaque constants
    that appear under a theorem root (subject to the same policy attrs/axioms). -/
private def rootValue?
    (info : ConstantInfo) : Except InlineProofAuditErrorV1 Expr :=
  match info with
  | .thmInfo v => pure v.value
  | .opaqueInfo _ =>
      err (.kindRejected info.name "product root must be a theorem (opaque rejected)")
  | .defnInfo _ =>
      err (.kindRejected info.name "product root must be a theorem")
  | .axiomInfo _ =>
      err (.kindRejected info.name "root must not be an axiom")
  | .quotInfo _ | .inductInfo _ | .ctorInfo _ | .recInfo _ =>
      err (.kindRejected info.name "product root must be a theorem")

/-- Collect type/value expressions that feed the dependency walk. -/
private def constantExprs (info : ConstantInfo) : Array Expr :=
  match info with
  | .thmInfo v => #[v.type, v.value]
  | .defnInfo v => #[v.type, v.value]
  | .opaqueInfo v => #[v.type, v.value]
  | .axiomInfo v => #[v.type]
  | .quotInfo v => #[v.type]
  | .inductInfo v => #[v.type]
  | .ctorInfo v => #[v.type]
  | .recInfo v => #[v.type]

/-- True when any expression contains `sorryAx`. -/
private def exprsHaveSorry (exprs : Array Expr) : Bool :=
  exprs.any Expr.hasSorry

/-- Push constant dependencies from expressions onto the worklist. -/
private def enqueueConstants
    (exprs : Array Expr) (seen : NameSet) (work : Array Name) :
    NameSet × Array Name :=
  Id.run do
    let mut seen := seen
    let mut work := work
    for e in exprs do
      for c in e.getUsedConstants do
        unless seen.contains c do
          seen := seen.insert c
          work := work.push c
    pure (seen, work)

/-- For inductive types, also walk constructors (mirrors CollectAxioms). -/
private def enqueueInductiveCtors
    (info : ConstantInfo) (seen : NameSet) (work : Array Name) :
    NameSet × Array Name :=
  match info with
  | .inductInfo v =>
      Id.run do
        let mut seen := seen
        let mut work := work
        for ctor in v.ctors do
          unless seen.contains ctor do
            seen := seen.insert ctor
            work := work.push ctor
        pure (seen, work)
  | _ => (seen, work)

/-- Audit a single constant already known to be in the dependency closure. -/
private def auditClosureConstant
    (env : Environment) (owner : Name) (name : Name) :
    Except InlineProofAuditErrorV1 (Array Expr × ConstantInfo) := do
  let info ← match env.find? name with
    | some info => pure info
    | none =>
        -- Missing constants are not trusted ambient fallbacks.
        err (.missingDeclaration name)
  if info.isUnsafe then
    return ← err (.unsafeDecl name)
  if info.isPartial then
    return ← err (.partialDecl name)
  rejectForbiddenAttrs env name
  match info with
  | .axiomInfo _ =>
      if name == ``sorryAx then
        return ← err (.forbiddenAxiom owner name)
      unless isAllowedBaseAxiomNameV1 name do
        return ← err (.forbiddenAxiom owner name)
  | _ => pure ()
  let exprs := constantExprs info
  if exprsHaveSorry exprs then
    return ← err (.sorryInDecl name)
  pure (exprs, info)

/-- Recursive type/value dependency closure audit from roots. -/
private def auditDependencyClosureV1
    (env : Environment) (owner : Name) (seedExprs : Array Expr) :
    Except InlineProofAuditErrorV1 Unit := do
  let (seen0, work0) := enqueueConstants seedExprs {} #[]
  let mut seen := seen0
  let mut work := work0
  let mut idx : Nat := 0
  while h : idx < work.size do
    let name := work[idx]
    idx := idx + 1
    let (exprs, info) ← auditClosureConstant env owner name
    let (seen1, work1) := enqueueConstants exprs seen work
    let (seen2, work2) := enqueueInductiveCtors info seen1 work1
    seen := seen2
    work := work2
  pure ()

/-- Kernel definitional equality on closed types (empty local context). -/
private def kernelTypeDefEq
    (env : Environment) (actual expected : Expr) (name : Name) :
    Except InlineProofAuditErrorV1 Unit :=
  match Kernel.isDefEq env {} actual expected with
  | .ok true => pure ()
  | .ok false => err (.typeNotDefEq name)
  | .error _ => err (.kernelFailure s!"{name}: kernel isDefEq failed")

/-- Audit one expected root theorem against the Environment. -/
private def auditOneExpectedV1
    (env : Environment) (expected : ExpectedInlineTheoremV1) :
    Except InlineProofAuditErrorV1 Name := do
  let name := expected.name
  let info ← match env.find? name with
    | some info => pure info
    | none => err (.missingDeclaration name)
  if info.isUnsafe then
    return ← err (.unsafeDecl name)
  if info.isPartial then
    return ← err (.partialDecl name)
  rejectForbiddenAttrs env name
  let value ← rootValue? info
  let actualType := info.type
  kernelTypeDefEq env actualType expected.expectedType name
  if actualType.hasSorry || value.hasSorry then
    return ← err (.sorryInDecl name)
  -- Seed closure with type + value of the root (root itself already checked).
  auditDependencyClosureV1 env name #[actualType, value]
  pure name

/-- Audit every expected theorem; all-or-nothing. -/
def auditExpectedTheoremsV1
    (env : Environment)
    (expected : Array ExpectedInlineTheoremV1) :
    Except InlineProofAuditErrorV1 InlineProofAuditReportV1 := do
  let policy ← match mintInlineProofPolicyV1 with
    | .ok p => pure p
    | .error (.internal d) => err (.policy d)
  let mut audited : Array Name := #[]
  for row in expected do
    audited := audited.push (← auditOneExpectedV1 env row)
  pure ⟨policy.digest, policy.version, audited⟩

end ProofForgeV2.Compiler.InlineProofAuditV1
