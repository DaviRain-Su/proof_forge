/-
  Tests.Semantic.ProofSubjectV1 — engineering proof-subject authority pins.

  These tests exercise the sole production builder with real parser spans and
  production semantic/provenance encoders. They are not formal TST-PROOF-001
  evidence and do not load `.olean` declarations.
-/
import Tests.Language.ParserSession
import Tests.Semantic.ProofSubjectGeneratedFixtureV1
import ProofForgeV2.Semantic.ProofReferenceJoinV1
import ProofForgeV2.Semantic.ProofSubjectV1

namespace Tests.Semantic.ProofSubjectV1

open ProofForgeV2
open ProofForgeV2.Core.Common
open ProofForgeV2.Semantic.NormalizeV1
open ProofForgeV2.Semantic.ProofBundleV1
open ProofForgeV2.Semantic.ProofReferenceJoinV1
open ProofForgeV2.Semantic.ProofSubjectV1
open ProofForgeV2.Semantic.WireV1
open ProofForgeV2.Source.SpanV1
open ProofForgeV2.Source.ValidatedSourceV1
open ProofForgeV2.Source.WireV1

/-- The generated module elaborates and both abbreviations reduce transparently. -/
example :
    ProofForgeV2.Generated.ProofSubjectV1.subjectProgram.canonicalBytes =
      ProofForgeV2.Generated.ProofSubjectV1.subjectBytes := rfl

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def sourcePath (label : String) : String :=
  "tests/proof-subject-" ++ label ++ ".pf"

private def sourceText (name : String) (literal : Nat) : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program " ++ name ++ " where\n" ++
  "  entry truth() : UInt64 do\n" ++
  "    return " ++ toString literal ++ "\n"

private unsafe def loadSourceWithSpans
    (session : Language.Loader.ParserSession) (label name : String) (literal : Nat) :
    IO (ValidatedSourceV1 × Array (NormalizedSyntacticPathV1 × SourceByteSpanV1)) := do
  match ← session.selectProgramV1WithSpans
      (sourceText name literal) (sourcePath label) "Tests.ProofSubjectV1" none with
  | .ok pair => pure pair
  | .error error => throw <| IO.userError s!"{label}: load failed: {error.render}"

private def parsePath (label : String) : IO ProjectRelativePath := do
  match parseProjectRelativePath (sourcePath label) with
  | .ok path => pure path
  | .error error => throw <| IO.userError s!"{label}: path: {error}"

private def encodeProvenance (provenance : SemanticProvenanceV1) : IO ByteArray := do
  match encodeSemanticProvenanceV1 provenance with
  | .ok bytes => pure bytes
  | .error error => throw <| IO.userError s!"encode provenance: {repr error}"

private def qn (components : Array String) : IO QualifiedName := do
  match parseQualifiedName components with
  | .ok name => pure name
  | .error error => throw <| IO.userError s!"qualified name: {error}"

private def openMatchingBundle
    (sourceHash semanticHash provenanceDigest : Digest) :
    IO OpenedProofBundleV1 := do
  let abiModuleName ← qn proofAbiModuleComponentsV1
  let abiTheoremName ← qn proofAbiTheoremComponentsV1
  let exportTheoremName ← qn #["Bundle", "Thm"]
  let moduleName ← qn #["Bundle", "Root"]
  let trustPolicyDigest ← match proofTrustPolicyDigestV1 with
    | .ok value => pure value
    | .error error => throw <| IO.userError s!"trust policy: {repr error}"
  let toolchainLockDigest ← match ProofForgeV2.Core.ToolLockV4.embeddedToolLockV4Identity with
    | .ok identity => pure identity.digest
    | .error error => throw <| IO.userError s!"Tool Lock v4: {error}"
  let oleanPath := "modules/Bundle/Root.olean"
  let oleanBytes := "proof-subject-join-olean".toUTF8
  let proofModule : ProofModuleV1 := {
    moduleName := moduleName
    oleanPath := oleanPath
    oleanDigest := sha256Bytes oleanBytes
    imports := #[] }
  let modules ← match NonEmptyArray.ofArray #[proofModule] with
    | .ok value => pure value
    | .error error => throw <| IO.userError error
  let proofExport : ProofExportV1 := {
    invariantName := "truth"
    invariantOrdinal := 0
    theoremName := exportTheoremName
    ownerModule := moduleName }
  let exports ← match NonEmptyArray.ofArray #[proofExport] with
    | .ok value => pure value
    | .error error => throw <| IO.userError error
  let roots ← match NonEmptyArray.ofArray #[moduleName] with
    | .ok value => pure value
    | .error error => throw <| IO.userError error
  let manifest : ProofBundleManifestV1 := {
    schema := proofBundleSchemaV1
    sourceHash
    semanticHash
    semanticProvenanceDigest := provenanceDigest
    toolchainLockDigest
    proofAbi := {
      semanticSchema := proofAbiSemanticSchemaV1
      moduleName := abiModuleName
      theoremName := abiTheoremName
      abiOleanDigest := sha256Bytes "abi".toUTF8
      trustPolicyDigest
      trustedBaseClosureDigest := sha256Bytes "closure".toUTF8 }
    roots
    modules
    exports }
  let manifestBytes ← match encodeProofBundleManifestV1 manifest with
    | .ok value => pure value.toUTF8
    | .error error => throw <| IO.userError s!"manifest encode: {repr error}"
  match openProofBundleV1 manifestBytes #[(oleanPath, oleanBytes)] with
  | .ok opened => pure opened
  | .error error => throw <| IO.userError s!"bundle open: {repr error}"

private def buildPositive
    (source : ValidatedSourceV1)
    (path : ProjectRelativePath)
    (spans : Array (NormalizedSyntacticPathV1 × SourceByteSpanV1)) :
    IO (SemanticProgramV1 × SemanticProvenanceV1 × ByteArray × ProofSubjectV1) := do
  let (carrier, provenance) ← match
      normalizeProgramWithProvenanceV1 source path spans with
    | .ok pair => pure pair
    | .error error => throw <| IO.userError s!"normalize: {repr error}"
  let pfprov ← encodeProvenance provenance
  let subject ← match buildProofSubjectV1
      source path spans carrier.canonicalBytes pfprov with
    | .ok value => pure value
    | .error error => throw <| IO.userError s!"subject: {repr error}"
  pure (carrier, provenance, pfprov, subject)

private unsafe def testPositiveAndClosedSource
    (session : Language.Loader.ParserSession) : IO Unit := do
  let (source, spans) ← loadSourceWithSpans session "positive" "SubjectPositive" 7
  let path ← parsePath "positive"
  let (carrier, provenance, _, subject) ← buildPositive source path spans
  let expectedSourceHash ← match sourceHashV1 source with
    | .ok digest => pure digest
    | .error error => throw <| IO.userError error
  let expectedSemanticHash ← match semanticHashV1 carrier with
    | .ok digest => pure digest
    | .error error => throw <| IO.userError s!"{repr error}"
  let expectedProvenanceDigest ← match semanticProvenanceDigestV1
      source path spans carrier provenance with
    | .ok digest => pure digest
    | .error error => throw <| IO.userError s!"{repr error}"
  expect (subject.program == carrier) "positive: exact semantic carrier"
  expect (subject.provenance == provenance) "positive: exact provenance"
  expect (subject.sourceHash == expectedSourceHash) "positive: sourceHash recomputed"
  expect (subject.semanticHash == expectedSemanticHash) "positive: semanticHash recomputed"
  expect (subject.semanticProvenanceDigest == expectedProvenanceDigest)
    "positive: provenance digest recomputed"
  let decimalBytes := String.intercalate ", " <|
    carrier.canonicalBytes.data.toList.map fun byte => toString byte.toNat
  let expectedLean :=
    "import ProofForgeV2.Semantic.WireV1\n\n" ++
    "namespace ProofForgeV2.Generated.ProofSubjectV1\n\n" ++
    "abbrev subjectBytes : ByteArray :=\n" ++
    "  ByteArray.mk #[" ++ decimalBytes ++ "]\n\n" ++
    "abbrev subjectProgram :\n" ++
    "    ProofForgeV2.Semantic.WireV1.SemanticProgramV1 :=\n" ++
    "  ⟨subjectBytes⟩\n\n" ++
    "end ProofForgeV2.Generated.ProofSubjectV1\n"
  expect (subject.closedLeanSource == expectedLean)
    "positive: frozen source contains every canonical byte"
  expect (subject.program.canonicalBytes ==
      ProofForgeV2.Generated.ProofSubjectV1.subjectBytes)
    "positive: generated fixture embeds exact validated carrier bytes"
  expect (!subject.closedLeanSource.contains "...") "positive: no byte ellipsis"
  let (_, _, _, repeated) ← buildPositive source path spans
  expect (repeated.closedLeanSource == subject.closedLeanSource)
    "positive: source generation deterministic"

private unsafe def testTransportPriorityAndAuthority
    (session : Language.Loader.ParserSession) : IO Unit := do
  let (source, spans) ← loadSourceWithSpans session "authority" "SubjectAuthority" 7
  let path ← parsePath "authority"
  let (carrier, _, pfprov, _) ← buildPositive source path spans
  let empty := ByteArray.empty
  expect (match buildProofSubjectV1 source path spans empty empty with
    | .error (.semanticProgramWire _) => true
    | _ => false) "priority: malformed semantic program first"
  expect (match buildProofSubjectV1 source path spans carrier.canonicalBytes empty with
    | .error (.semanticProvenanceWire _) => true
    | _ => false) "priority: malformed provenance second"
  let wrongPath ← parsePath "wrong-authority"
  expect (match buildProofSubjectV1
      source wrongPath spans carrier.canonicalBytes pfprov with
    | .error (.authority _) => true
    | _ => false) "authority: wrong trusted path rejected"
  expect (!spans.isEmpty) "authority: expected nonempty trusted spans"
  let changedSpans := spans.map fun (nodePath, span) =>
    (nodePath, { span with endByte := span.endByte + 1 })
  expect (match buildProofSubjectV1
      source path changedSpans carrier.canonicalBytes pfprov with
    | .error (.authority _) => true
    | _ => false) "authority: wrong trusted spans rejected"
  let (otherSource, otherSpans) ←
    loadSourceWithSpans session "other" "SubjectOther" 8
  let otherPath ← parsePath "other"
  let (otherCarrier, _, otherPfprov, _) ←
    buildPositive otherSource otherPath otherSpans
  -- This is a canonical, structure-valid carrier, not a corrupt-byte negative.
  expect (match buildProofSubjectV1
      source path spans otherCarrier.canonicalBytes pfprov with
    | .error (.authority _) => true
    | _ => false) "authority: canonical semantic substitution rejected"
  -- This companion also strictly decodes and re-encodes before its source join fails.
  expect (match buildProofSubjectV1
      source path spans carrier.canonicalBytes otherPfprov with
    | .error (.authority _) => true
    | _ => false) "authority: canonical provenance substitution rejected"

private unsafe def testManifestDigestJoin
    (session : Language.Loader.ParserSession) : IO Unit := do
  let (source, spans) ← loadSourceWithSpans session "manifest" "SubjectManifest" 9
  let path ← parsePath "manifest"
  let (_, _, _, subject) ← buildPositive source path spans
  let bindings : Array SourceProofBindingV1 :=
    #[{ invariantName := "truth", theoremComponents := #["Bundle", "Thm"] }]
  let opened ← openMatchingBundle subject.sourceHash subject.semanticHash
    subject.semanticProvenanceDigest
  match joinValidatedProofSubjectV1 bindings opened opened.bundleDigest subject with
  | .ok () => pure ()
  | .error error => throw <| IO.userError s!"manifest join: {repr error}"
  let wrong := sha256Bytes "wrong-proof-subject-digest".toUTF8
  let wrongSource ← openMatchingBundle wrong subject.semanticHash
    subject.semanticProvenanceDigest
  expect (match joinValidatedProofSubjectV1
      bindings wrongSource wrongSource.bundleDigest subject with
    | .error .sourceHashMismatch => true
    | _ => false) "manifest join: sourceHash claim rejected"
  let wrongSemantic ← openMatchingBundle subject.sourceHash wrong
    subject.semanticProvenanceDigest
  expect (match joinValidatedProofSubjectV1
      bindings wrongSemantic wrongSemantic.bundleDigest subject with
    | .error .semanticHashMismatch => true
    | _ => false) "manifest join: semanticHash claim rejected"
  let wrongProvenance ← openMatchingBundle subject.sourceHash subject.semanticHash wrong
  expect (match joinValidatedProofSubjectV1
      bindings wrongProvenance wrongProvenance.bundleDigest subject with
    | .error .semanticProvenanceDigestMismatch => true
    | _ => false) "manifest join: provenance digest claim rejected"

unsafe def run : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  testPositiveAndClosedSource session
  testTransportPriorityAndAuthority session
  testManifestDigestJoin session
  IO.println "Tests.Semantic.ProofSubjectV1: ok"

end Tests.Semantic.ProofSubjectV1
