import ProofForgeV2.Semantic.ProofSubjectV1

/-
  ProofForgeV2.Compiler.ProofSubjectFilesV1 — compiler-core filesystem adapter
  for the immutable proof-subject pair.

  The native operation opens one trusted absolute root component-by-component,
  retains one dirfd, and stable-reads the two fixed regular single-link files.
  Semantic validation remains solely in `Semantic.ProofSubjectV1`.

  This is an engineering foundation, not a contained worker, deadline/memory
  supervisor, `.olean` loader, or formal TST-PROOF-001 completion.
-/

namespace ProofForgeV2.Compiler.ProofSubjectFilesV1

open ProofForgeV2.Core.Common
open ProofForgeV2.Semantic.ProofSubjectV1
open ProofForgeV2.Semantic.WireV1
open ProofForgeV2.Source.SpanV1
open ProofForgeV2.Source.ValidatedSourceV1
open ProofForgeV2.Source.WireV1
open System

def semanticProgramFileNameV1 : String := "proof-subject.pfsem"
def semanticProvenanceFileNameV1 : String := "proof-subject.pfprov"

inductive ProofSubjectFileV1 where
  | semanticProgram
  | semanticProvenance
  deriving BEq, DecidableEq, Repr

inductive StableFileFaultV1 where
  | notFound
  | permissionDenied
  | unsafePath
  | nonRegular
  | multipleLinks
  | tooLarge
  | shortRead
  | grewDuringRead
  | changedDuringRead
  | io
  deriving BEq, DecidableEq, Repr

namespace StableFileFaultV1

def wire : StableFileFaultV1 → String
  | .notFound => "not-found"
  | .permissionDenied => "permission-denied"
  | .unsafePath => "unsafe-path"
  | .nonRegular => "non-regular"
  | .multipleLinks => "multiple-links"
  | .tooLarge => "too-large"
  | .shortRead => "short-read"
  | .grewDuringRead => "grew-during-read"
  | .changedDuringRead => "changed-during-read"
  | .io => "io"

def ofWire? : String → Option StableFileFaultV1
  | "not-found" => some .notFound
  | "permission-denied" => some .permissionDenied
  | "unsafe-path" => some .unsafePath
  | "non-regular" => some .nonRegular
  | "multiple-links" => some .multipleLinks
  | "too-large" => some .tooLarge
  | "short-read" => some .shortRead
  | "grew-during-read" => some .grewDuringRead
  | "changed-during-read" => some .changedDuringRead
  | "io" => some .io
  | _ => none

end StableFileFaultV1

inductive ProofSubjectFilesErrorV1 where
  | invalidRoot
  | root (fault : StableFileFaultV1)
  | file (file : ProofSubjectFileV1) (fault : StableFileFaultV1)
  | nativeProtocol
  | subject (error : ProofSubjectErrorV1)
  deriving Repr

@[extern "proof_forge_read_proof_subject_files_v1"]
private opaque nativeReadProofSubjectFilesV1
    (root : @& String) (maxBytes : UInt64) :
    IO (Except String (ByteArray × ByteArray))

private def containsNul (value : String) : Bool :=
  value.toList.any (· == '\x00')

private def parseScopedFault
    (wire : String) : ProofSubjectFilesErrorV1 :=
  if wire == "invalid-root" then
    .invalidRoot
  else
    match wire.splitOn ":" with
    | [scope, detail] =>
        match StableFileFaultV1.ofWire? detail with
        | none => .nativeProtocol
        | some fault =>
            if scope == "root" then .root fault
            else if scope == "semantic-program" then
              .file .semanticProgram fault
            else if scope == "semantic-provenance" then
              .file .semanticProvenance fault
            else .nativeProtocol
    | _ => .nativeProtocol

/-- Stable-read the fixed proof-subject pair and delegate all data authority to
    `buildProofSubjectV1`. No file names, inventories, or digests are supplied
    by the caller. -/
def loadProofSubjectFilesV1
    (root : FilePath)
    (source : ValidatedSourceV1)
    (sourcePath : ProjectRelativePath)
    (trustedSpans :
      Array (NormalizedSyntacticPathV1 × SourceByteSpanV1)) :
    IO (Except ProofSubjectFilesErrorV1 ProofSubjectV1) := do
  let rootString := root.toString
  if !root.isAbsolute || rootString.isEmpty || containsNul rootString then
    return .error .invalidRoot
  match ← nativeReadProofSubjectFilesV1
      rootString (UInt64.ofNat maxCanonicalProgramBytes) with
  | .error wire => pure (.error (parseScopedFault wire))
  | .ok (semanticBytes, provenanceBytes) =>
      if semanticBytes.size > maxCanonicalProgramBytes ||
          provenanceBytes.size > maxCanonicalProgramBytes ||
          semanticBytes.size + provenanceBytes.size >
            2 * maxCanonicalProgramBytes then
        pure (.error .nativeProtocol)
      else
        match buildProofSubjectV1 source sourcePath trustedSpans
            semanticBytes provenanceBytes with
        | .ok subject => pure (.ok subject)
        | .error error => pure (.error (.subject error))

end ProofForgeV2.Compiler.ProofSubjectFilesV1
