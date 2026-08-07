import ProofForgeV2.Core.Common
import ProofForgeV2.Source.AstProgramV1
import ProofForgeV2.Source.AstProgramItemV1
import ProofForgeV2.Source.AstV1
import ProofForgeV2.Source.NameComponentV1
import ProofForgeV2.Source.QualifiedNameV1
import ProofForgeV2.Semantic.ProofBundleV1
import ProofForgeV2.Semantic.ProofSubjectV1

/-
  ProofForgeV2.Semantic.ProofReferenceJoinV1 — engineering **INV-1** constrained
  library-only proof-reference join (not product CLI; not formal TST-PROOF-001).
  Product `check`/`build` use `Compiler.certifyInlineProofV1` exclusively.

  Scope:
    * Collect source-order holds/preserving proof bindings from ProgramV1
    * Exact set join of source bindings ↔ holds-only ProofBundleV1 exports
      `(invariantName, kind, theoremComponents)`; preserving fails closed
    * Caller-supplied expected digest + sourceHash + semanticHash must match opened bundle
    * No ambient Lean term / Environment / definitional equality / olean kernel

  Out of scope: trust-policy axiom graph, toolchain lock pin, contained worker,
  ordinal/InvariantTheoremV1 definitional equality, formal Stage-0.
-/

namespace ProofForgeV2.Semantic.ProofReferenceJoinV1

open ProofForgeV2.Core.Common
open ProofForgeV2.Source.AstProgramV1
open ProofForgeV2.Source.AstProgramItemV1
open ProofForgeV2.Source.AstV1
open ProofForgeV2.Source.NameComponentV1
open ProofForgeV2.Source.QualifiedNameV1
open ProofForgeV2.Semantic.ProofBundleV1
open ProofForgeV2.Semantic.ProofSubjectV1

/-- One source-level proof reference binding (certification metadata only). -/
structure SourceProofBindingV1 where
  invariantName : String
  kind : ProofKindV1
  theoremComponents : Array String
  deriving BEq, Repr, Inhabited

/-- Closed library-join errors (engineering). -/
inductive ProofReferenceJoinErrorV1 where
  | unusedBundle
  | missingBundle
  | digestMismatch (detail : String)
  | sourceHashMismatch
  | semanticHashMismatch
  | semanticProvenanceDigestMismatch
  | exportMismatch (detail : String)
  | bundleOpen (err : ProofBundleErrorV1)
  | internal (detail : String)
  deriving BEq, Repr

private def err (e : ProofReferenceJoinErrorV1) : Except ProofReferenceJoinErrorV1 α :=
  .error e

/-- Source-order collection of `proof` declarations (empty when none). -/
def collectSourceProofBindingsV1 (program : ProgramV1) : Array SourceProofBindingV1 :=
  Id.run do
    let mut out : Array SourceProofBindingV1 := #[]
    for item in program.items do
      match item with
      | .proof d =>
          let inv := d.invariant.raw
          let thm :=
            (NonEmptyArray.toArray d.theorem_.components).map
              (fun c => c.raw)
          out := out.push {
            invariantName := inv
            kind := d.kind
            theoremComponents := thm
          }
      | _ => pure ()
    pure out

private structure BindingKeyV1 where
  invariantName : String
  kind : ProofKindV1
  theoremComponents : Array String
  deriving BEq, Inhabited

/-- Source keys retain proof kind. Historical ProofBundle exports are explicitly
    holds-only, so a preserving source binding cannot alias a holds export. -/
private def bindingKey (b : SourceProofBindingV1) : BindingKeyV1 :=
  { invariantName := b.invariantName, kind := b.kind,
    theoremComponents := b.theoremComponents }

private def exportKey (e : ProofExportV1) : BindingKeyV1 :=
  { invariantName := e.invariantName, kind := .holds,
    theoremComponents := e.theoremName.components.toArray }

private def kindRank : ProofKindV1 → Nat
  | .holds => 0
  | .preserving => 1

/-- Lexicographic order on `(invariantName, kind, theoremComponents)` for stable
    sort. Returns true when `a` is strictly less than `b`. -/
private def cmpKey (a b : BindingKeyV1) : Bool :=
  if a.invariantName < b.invariantName then true
  else if b.invariantName < a.invariantName then false
  else if kindRank a.kind < kindRank b.kind then true
  else if kindRank b.kind < kindRank a.kind then false
  else
    -- Component-wise: use zip-with remaining length fuel.
    let ac := a.theoremComponents.toList
    let bc := b.theoremComponents.toList
    let rec loop (xs ys : List String) : Bool :=
      match xs, ys with
      | [], [] => false
      | [], _ :: _ => true
      | _ :: _, [] => false
      | x :: xs', y :: ys' =>
          if x < y then true
          else if y < x then false
          else loop xs' ys'
    loop ac bc

private partial def insertSorted
    (xs : Array BindingKeyV1) (k : BindingKeyV1) :
    Array BindingKeyV1 :=
  Id.run do
    let mut out : Array BindingKeyV1 := #[]
    let mut placed := false
    for x in xs do
      if !placed && cmpKey k x then
        out := out.push k
        placed := true
      out := out.push x
    if !placed then
      out := out.push k
    pure out

private def sortKeys (keys : Array BindingKeyV1) : Array BindingKeyV1 :=
  Id.run do
    let mut out : Array BindingKeyV1 := #[]
    for k in keys do
      out := insertSorted out k
    pure out

/-- Exact set equality of source bindings vs bundle exports (order-insensitive).
    Duplicates on either side fail closed. -/
private def exactBindingExportJoin
    (bindings : Array SourceProofBindingV1)
    (exports : Array ProofExportV1) :
    Except ProofReferenceJoinErrorV1 Unit := do
  let srcKeys := sortKeys (bindings.map bindingKey)
  let expKeys := sortKeys (exports.map exportKey)
  -- Reject duplicates after sort (adjacent equal).
  let rec noDup (arr : Array BindingKeyV1) (i : Nat) (side : String) :
      Except ProofReferenceJoinErrorV1 Unit := do
    if h : i + 1 < arr.size then
      let a := arr[i]!
      let b := arr[i + 1]!
      if a == b then
        return ← err (.exportMismatch
          s!"duplicate {side} binding {a.invariantName}/{a.kind}")
      noDup arr (i + 1) side
    else pure ()
  noDup srcKeys 0 "source"
  noDup expKeys 0 "export"
  unless srcKeys.size == expKeys.size do
    return ← err (.exportMismatch
      s!"source has {srcKeys.size} proof reference(s), bundle exports {expKeys.size}")
  let mut i : Nat := 0
  for sk in srcKeys do
    let ek := expKeys[i]!
    unless sk == ek do
      let detail :=
        s!"source/export set mismatch at sorted index {i}: source=" ++
        s!"({sk.invariantName}/{sk.kind}) export=" ++
        s!"({ek.invariantName}/{ek.kind})"
      return ← err (.exportMismatch detail)
    i := i + 1
  pure ()

/-- Transitional, library-only join retained for focused compatibility tests.
    Product CLI proof certification does not call this module. Library callers
    that require provenance use `joinValidatedProofSubjectV1` below.

    Rules (engineering library subset of SPEC-SEM-001):
    * expectedBundleDigest == opened.bundleDigest
    * manifest.sourceHash == sourceHash
    * manifest.semanticHash == semanticHash
    * source proof set == holds-only export set on
      (invariantName, kind, theoremComponents)
    * empty bindings ⇒ `.unusedBundle` (caller should not open when unused)
-/
def joinProofReferencesV1
    (bindings : Array SourceProofBindingV1)
    (opened : OpenedProofBundleV1)
    (expectedBundleDigest : Digest)
    (sourceHash : Digest)
    (semanticHash : Digest) :
    Except ProofReferenceJoinErrorV1 Unit := do
  if bindings.isEmpty then
    return ← err .unusedBundle
  unless opened.bundleDigest.bytes == expectedBundleDigest.bytes do
    return ← err (.digestMismatch "expected proof-bundle digest does not match opened bundle")
  unless opened.manifest.sourceHash.bytes == sourceHash.bytes do
    return ← err .sourceHashMismatch
  unless opened.manifest.semanticHash.bytes == semanticHash.bytes do
    return ← err .semanticHashMismatch
  exactBindingExportJoin bindings (NonEmptyArray.toArray opened.manifest.exports)

/-- Complete digest/reference join from a sealed, source-bound proof subject.

    Unlike the transitional compile-digest join above, this path also requires
    the manifest provenance digest to equal the authority-recomputed digest.
    Manifest fields remain claims only and never mint a `ProofSubjectV1`. -/
def joinValidatedProofSubjectV1
    (bindings : Array SourceProofBindingV1)
    (opened : OpenedProofBundleV1)
    (expectedBundleDigest : Digest)
    (subject : ProofSubjectV1) :
    Except ProofReferenceJoinErrorV1 Unit := do
  if bindings.isEmpty then
    return ← err .unusedBundle
  unless opened.bundleDigest.bytes == expectedBundleDigest.bytes do
    return ← err (.digestMismatch
      "expected proof-bundle digest does not match opened bundle")
  unless opened.manifest.sourceHash.bytes == subject.sourceHash.bytes do
    return ← err .sourceHashMismatch
  unless opened.manifest.semanticHash.bytes == subject.semanticHash.bytes do
    return ← err .semanticHashMismatch
  unless opened.manifest.semanticProvenanceDigest.bytes ==
      subject.semanticProvenanceDigest.bytes do
    return ← err .semanticProvenanceDigestMismatch
  exactBindingExportJoin bindings (NonEmptyArray.toArray opened.manifest.exports)

/-- Library compatibility gate: decide whether a bundle is required / forbidden.

    Returns:
    * `.ok none` — no proofs and no pair (normal)
    * `.ok (some ())` placeholder not used; callers use pair presence
    * errors for missing/unused before open

    Pure pair-presence gate (open+join is separate). -/
def requireProofBundlePairGateV1
    (bindings : Array SourceProofBindingV1)
    (pairPresent : Bool) :
    Except ProofReferenceJoinErrorV1 Unit := do
  match bindings.isEmpty, pairPresent with
  | true, false => pure ()
  | true, true => err .unusedBundle
  | false, false => err .missingBundle
  | false, true => pure ()

/-- Human-stable library diagnostic used by compatibility tests and callers. -/
def renderProofReferenceJoinErrorV1 (e : ProofReferenceJoinErrorV1) : String :=
  match e with
  | .unusedBundle =>
      "proof-bundle is not accepted: source has no proof references"
  | .missingBundle =>
      "source proof references require a proof bundle and expected digest in this library API"
  | .digestMismatch detail => s!"proof-bundle digest mismatch: {detail}"
  | .sourceHashMismatch =>
      "proof-bundle sourceHash does not match compiled source"
  | .semanticHashMismatch =>
      "proof-bundle semanticHash does not match compiled semantic"
  | .semanticProvenanceDigestMismatch =>
      "proof-bundle semanticProvenanceDigest does not match validated proof subject"
  | .exportMismatch detail => s!"proof-bundle export join failed: {detail}"
  | .bundleOpen pe =>
      match pe with
      | .malformed d => s!"proof-bundle malformed: {d}"
      | .toolchainLockMismatch d => s!"proof-bundle Tool Lock mismatch: {d}"
      | .digestMismatch d => s!"proof-bundle module digest: {d}"
      | .missingModule p => s!"proof-bundle missing module file: {p}"
      | .extraModule p => s!"proof-bundle extra module file: {p}"
      | .internal d => s!"proof-bundle internal: {d}"
  | .internal detail => s!"proof-bundle internal: {detail}"

end ProofForgeV2.Semantic.ProofReferenceJoinV1
