/-
  Tests.Semantic.ProofBundleV1 — engineering R-3 safe load pins.

  Drives shipped `openProofBundleV1` / `decodeProofBundleManifestV1` /
  `proofBundleDigestV1` (not a re-implementation). Covers:
    * well-formed minimal bundle (manifest + one module file)
    * wrong schema fail closed
    * non-canonical PF-JCS (trailing whitespace) fail closed
    * oleanDigest mismatch fail closed
    * missing module file fail closed
    * extra module file fail closed
    * digest determinism
-/
import ProofForgeV2.Core.Common
import ProofForgeV2.Semantic.ProofBundleV1

namespace Tests.Semantic.ProofBundleV1

open ProofForgeV2.Core.Common
open ProofForgeV2.Semantic.ProofBundleV1

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def qn (comps : Array String) : IO QualifiedName :=
  match parseQualifiedName comps with
  | .ok q => pure q
  | .error e => throw <| IO.userError s!"qn: {e}"

private def fixedDigest (tag : UInt8) : Digest :=
  sha256Bytes (ByteArray.mk #[tag, 1, 2, 3])

private def mkMinimalManifest (oleanPath : String) (oleanDigest : Digest) :
    IO ProofBundleManifestV1 := do
  let moduleName ← qn proofAbiModuleComponentsV1
  let theoremName ← qn proofAbiTheoremComponentsV1
  let root ← qn #["Bundle", "Root"]
  let mod : ProofModuleV1 := {
    moduleName
    oleanPath
    oleanDigest
    imports := #[]
  }
  let ex : ProofExportV1 := {
    invariantName := "truth"
    invariantOrdinal := 0
    theoremName
    ownerModule := moduleName
  }
  let modules ← match NonEmptyArray.ofArray #[mod] with
    | .ok ne => pure ne
    | .error e => throw <| IO.userError e
  let exports ← match NonEmptyArray.ofArray #[ex] with
    | .ok ne => pure ne
    | .error e => throw <| IO.userError e
  let roots ← match NonEmptyArray.ofArray #[root] with
    | .ok ne => pure ne
    | .error e => throw <| IO.userError e
  pure {
    schema := proofBundleSchemaV1
    sourceHash := fixedDigest 0x11
    semanticHash := fixedDigest 0x22
    semanticProvenanceDigest := fixedDigest 0x33
    toolchainLockDigest := fixedDigest 0x44
    proofAbi := {
      semanticSchema := proofAbiSemanticSchemaV1
      moduleName
      theoremName
      abiOleanDigest := fixedDigest 0x55
      trustPolicyDigest := fixedDigest 0x66
      trustedBaseClosureDigest := fixedDigest 0x77
    }
    roots
    modules
    exports
  }

private def encodeManifestBytes (m : ProofBundleManifestV1) : IO ByteArray := do
  match encodeProofBundleManifestV1 m with
  | .ok s => pure s.toUTF8
  | .error e => throw <| IO.userError s!"encode: {repr e}"

/-- Positive: open a well-formed one-module bundle. -/
private def testOpenWellFormed : IO Unit := do
  let oleanPath := "modules/ProofForgeV2/Semantic/InvariantABI.olean"
  let oleanBytes := "olean-fixture-bytes-v1".toUTF8
  let oleanDigest := sha256Bytes oleanBytes
  let m ← mkMinimalManifest oleanPath oleanDigest
  let manBytes ← encodeManifestBytes m
  match openProofBundleV1 manBytes #[(oleanPath, oleanBytes)] with
  | .error e => throw <| IO.userError s!"well-formed open failed: {repr e}"
  | .ok opened => do
      expect (opened.manifest.schema == proofBundleSchemaV1) "schema pin"
      expect (opened.moduleFiles.size == 1) "one verified module"
      let d1 ← match proofBundleDigestV1 m with
        | .ok d => pure d
        | .error e => throw <| IO.userError s!"digest: {repr e}"
      expect (d1.bytes == opened.bundleDigest.bytes) "bundleDigest matches pure path"
      -- Re-open must be deterministic.
      match openProofBundleV1 manBytes #[(oleanPath, oleanBytes)] with
      | .error e => throw <| IO.userError s!"re-open failed: {repr e}"
      | .ok opened2 =>
          expect (opened2.bundleDigest.bytes == opened.bundleDigest.bytes)
            "digest deterministic"

/-- Wrong schema string fail closed. -/
private def testWrongSchema : IO Unit := do
  let oleanPath := "modules/A.olean"
  let oleanBytes := ByteArray.mk #[1, 2, 3]
  let m0 ← mkMinimalManifest oleanPath (sha256Bytes oleanBytes)
  let m := { m0 with schema := "proof-forge.proof-bundle.v0" }
  let manBytes ← encodeManifestBytes m
  match openProofBundleV1 manBytes #[(oleanPath, oleanBytes)] with
  | .ok _ => throw <| IO.userError "wrong schema must fail"
  | .error (.malformed detail) =>
      expect (detail.contains "schema") s!"detail={detail}"
  | .error e => throw <| IO.userError s!"wrong schema unexpected: {repr e}"

/-- Non-canonical PF-JCS (trailing newline) fail closed. -/
private def testNonCanonicalJcs : IO Unit := do
  let oleanPath := "modules/A.olean"
  let oleanBytes := ByteArray.mk #[9]
  let m ← mkMinimalManifest oleanPath (sha256Bytes oleanBytes)
  let manText ← match encodeProofBundleManifestV1 m with
    | .ok s => pure s
    | .error e => throw <| IO.userError s!"encode: {repr e}"
  let dirty := (manText ++ "\n").toUTF8
  match openProofBundleV1 dirty #[(oleanPath, oleanBytes)] with
  | .ok _ => throw <| IO.userError "non-canonical must fail"
  | .error (.malformed detail) =>
      expect (detail.contains "canonical" || detail.contains "PF-JCS")
        s!"detail={detail}"
  | .error e => throw <| IO.userError s!"non-canonical unexpected: {repr e}"

/-- Digest mismatch fail closed. -/
private def testOleanDigestMismatch : IO Unit := do
  let oleanPath := "modules/A.olean"
  let oleanBytes := ByteArray.mk #[7, 7, 7]
  let wrongDigest := sha256Bytes (ByteArray.mk #[0])
  let m ← mkMinimalManifest oleanPath wrongDigest
  let manBytes ← encodeManifestBytes m
  match openProofBundleV1 manBytes #[(oleanPath, oleanBytes)] with
  | .ok _ => throw <| IO.userError "digest mismatch must fail"
  | .error (.digestMismatch detail) =>
      expect (detail.contains "mismatch") s!"detail={detail}"
  | .error e => throw <| IO.userError s!"digest unexpected: {repr e}"

/-- Missing module file fail closed. -/
private def testMissingModule : IO Unit := do
  let oleanPath := "modules/A.olean"
  let oleanBytes := ByteArray.mk #[1]
  let m ← mkMinimalManifest oleanPath (sha256Bytes oleanBytes)
  let manBytes ← encodeManifestBytes m
  match openProofBundleV1 manBytes #[] with
  | .ok _ => throw <| IO.userError "missing module must fail"
  | .error (.missingModule path) =>
      expect (path == oleanPath) s!"path={path}"
  | .error e => throw <| IO.userError s!"missing unexpected: {repr e}"

/-- Extra module file fail closed. -/
private def testExtraModule : IO Unit := do
  let oleanPath := "modules/A.olean"
  let oleanBytes := ByteArray.mk #[1]
  let m ← mkMinimalManifest oleanPath (sha256Bytes oleanBytes)
  let manBytes ← encodeManifestBytes m
  match openProofBundleV1 manBytes
      #[(oleanPath, oleanBytes), ("modules/EXTRA.olean", ByteArray.mk #[2])] with
  | .ok _ => throw <| IO.userError "extra module must fail"
  | .error (.extraModule path) =>
      expect (path == "modules/EXTRA.olean") s!"path={path}"
  | .error e => throw <| IO.userError s!"extra unexpected: {repr e}"

unsafe def run : IO Unit := do
  testOpenWellFormed
  testWrongSchema
  testNonCanonicalJcs
  testOleanDigestMismatch
  testMissingModule
  testExtraModule
  IO.println "Tests.Semantic.ProofBundleV1: ok"

end Tests.Semantic.ProofBundleV1
