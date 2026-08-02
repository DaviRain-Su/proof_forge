/-
  Tests.Semantic.ProofBundleV1 — engineering R-3 in-memory authority pins.

  Drives shipped `openProofBundleV1` / `decodeProofBundleManifestV1` /
  `proofBundleDigestV1` (not a re-implementation). Covers:
    * well-formed minimal bundle (manifest + one module file)
    * wrong schema fail closed
    * non-canonical PF-JCS (trailing whitespace) fail closed
    * oleanDigest mismatch fail closed
    * missing module file fail closed
    * extra module file fail closed
    * digest determinism
    * module-derived paths and canonical manifest authority order
    * invalid direct carriers cannot mint bundle digests
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

private def fixedTrustPolicyDigest : IO Digest :=
  match proofTrustPolicyDigestV1 with
  | .ok value => pure value
  | .error error => throw <| IO.userError s!"trust policy: {repr error}"

private def mkMinimalManifest (oleanPath : String) (oleanDigest : Digest) :
    IO ProofBundleManifestV1 := do
  let abiModuleName ← qn proofAbiModuleComponentsV1
  let theoremName ← qn proofAbiTheoremComponentsV1
  let moduleName ← qn #["Bundle", "Root"]
  let trustPolicyDigest ← fixedTrustPolicyDigest
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
  let roots ← match NonEmptyArray.ofArray #[moduleName] with
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
      moduleName := abiModuleName
      theoremName
      abiOleanDigest := fixedDigest 0x55
      trustPolicyDigest
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

private def expectManifestMalformed
    (label : String) (manifest : ProofBundleManifestV1) (needle : String) : IO Unit := do
  match validateProofBundleManifestV1 manifest with
  | .ok () => throw <| IO.userError s!"{label}: unexpectedly accepted"
  | .error (.malformed detail) =>
      expect (detail.contains needle) s!"{label}: detail={detail}"
  | .error error => throw <| IO.userError s!"{label}: {repr error}"

private def expectManifestValid
    (label : String) (manifest : ProofBundleManifestV1) : IO Unit := do
  match validateProofBundleManifestV1 manifest with
  | .ok () => pure ()
  | .error error => throw <| IO.userError s!"{label}: {repr error}"

private def manifestWithGraph
    (base : ProofBundleManifestV1)
    (rows : Array (QualifiedName × Array QualifiedName)) : IO ProofBundleManifestV1 := do
  let modules ← match NonEmptyArray.ofArray (rows.map fun (name, imports) =>
      { base.modules.head with
        moduleName := name
        oleanPath := proofModuleOleanPathV1 name
        imports }) with
    | .ok value => pure value
    | .error error => throw <| IO.userError error
  let root ← match rows[0]? with
    | some row => pure row.1
    | none => throw <| IO.userError "graph manifest requires a module"
  let roots ← match NonEmptyArray.ofArray #[root] with
    | .ok value => pure value
    | .error error => throw <| IO.userError error
  let exports ← match NonEmptyArray.ofArray #[{ base.exports.head with ownerModule := root }] with
    | .ok value => pure value
    | .error error => throw <| IO.userError error
  pure { base with modules, roots, exports }

private def expectCycleRejected (label : String) (manifest : ProofBundleManifestV1) : IO Unit := do
  expectManifestMalformed label manifest "cycle"
  match proofBundleDigestV1 manifest with
  | .error (.malformed detail) => expect (detail.contains "cycle") s!"{label} digest: {detail}"
  | .error error => throw <| IO.userError s!"{label} digest: {repr error}"
  | .ok _ => throw <| IO.userError s!"{label}: cycle minted digest"

private def testDeclaredLoadPlansAndCycles : IO Unit := do
  let bytes := "graph-module".toUTF8
  let base ← mkMinimalManifest "modules/Bundle/Root.olean" (sha256Bytes bytes)
  let a ← qn #["Bundle", "A"]
  let b ← qn #["Bundle", "B"]
  let c ← qn #["Bundle", "C"]
  let d ← qn #["Bundle", "D"]
  let unknownA ← qn #["Trusted", "A"]
  let unknownZ ← qn #["Trusted", "Z"]
  let checkPlan (label : String) (manifest : ProofBundleManifestV1)
      (expectedOrder expectedUnknown : Array QualifiedName) : IO Unit := do
    let manifestBytes ← encodeManifestBytes manifest
    let files := (NonEmptyArray.toArray manifest.modules).map fun module =>
      (module.oleanPath, bytes)
    let opened ← match openProofBundleV1 manifestBytes files with
      | .ok value => pure value
      | .error error => throw <| IO.userError s!"{label} open: {repr error}"
    expect
      ((NonEmptyArray.toArray opened.manifest.modules).map (·.imports) ==
        (NonEmptyArray.toArray manifest.modules).map (·.imports))
      s!"{label}: decoded direct-import order"
    let plan ← match declaredProofBundleLoadPlanV1 opened with
      | .ok value => pure value
      | .error error => throw <| IO.userError s!"{label} plan: {repr error}"
    expect (plan.dependencyFirstModules == expectedOrder) s!"{label}: dependency order"
    expect (plan.unresolvedImportFrontier == expectedUnknown) s!"{label}: unresolved imports"

  let singleton ← manifestWithGraph base #[(a, #[])]
  checkPlan "singleton" singleton #[a] #[]
  let reversedDependency ← manifestWithGraph base #[(a, #[b]), (b, #[])]
  checkPlan "dependency first" reversedDependency #[b, a] #[]
  -- A diamond with canonical manifest rows deterministically selects B before C.
  let diamond ← manifestWithGraph base #[(a, #[c, b]), (b, #[d]), (c, #[d]), (d, #[])]
  let originalImports := diamond.modules.head.imports
  checkPlan "diamond" diamond #[d, b, c, a] #[]
  expect (diamond.modules.head.imports == originalImports) "plan mutated direct import order"
  let unknowns ← manifestWithGraph base #[(a, #[unknownZ, unknownA]),
    (b, #[unknownA, unknownZ])]
  checkPlan "unknown frontier" unknowns #[a, b] #[unknownA, unknownZ]
  expect (unknowns.modules.head.imports == #[unknownZ, unknownA])
    "unknown imports changed direct order"

  expectCycleRejected "self cycle" (← manifestWithGraph base #[(a, #[a])])
  expectCycleRejected "two-node cycle" (← manifestWithGraph base #[(a, #[b]), (b, #[a])])
  expectCycleRejected "three-node cycle"
    (← manifestWithGraph base #[(a, #[b]), (b, #[c]), (c, #[a])])
  expectCycleRejected "disconnected cycle"
    (← manifestWithGraph base #[(a, #[]), (b, #[c]), (c, #[b]), (d, #[a])])
  let disconnectedAcyclic ← manifestWithGraph base
    #[(a, #[b]), (b, #[]), (c, #[]), (d, #[c])]
  checkPlan "disconnected acyclic" disconnectedAcyclic #[b, a, c, d] #[]

/-- Positive: open a well-formed one-module bundle. -/
private def testOpenWellFormed : IO Unit := do
  let oleanPath := "modules/Bundle/Root.olean"
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
  let oleanPath := "modules/Bundle/Root.olean"
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
  let oleanPath := "modules/Bundle/Root.olean"
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
  let oleanPath := "modules/Bundle/Root.olean"
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
  let oleanPath := "modules/Bundle/Root.olean"
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
  let oleanPath := "modules/Bundle/Root.olean"
  let oleanBytes := ByteArray.mk #[1]
  let m ← mkMinimalManifest oleanPath (sha256Bytes oleanBytes)
  let manBytes ← encodeManifestBytes m
  match openProofBundleV1 manBytes
      #[(oleanPath, oleanBytes), ("modules/EXTRA.olean", ByteArray.mk #[2])] with
  | .ok _ => throw <| IO.userError "extra module must fail"
  | .error (.extraModule path) =>
      expect (path == "modules/EXTRA.olean") s!"path={path}"
  | .error e => throw <| IO.userError s!"extra unexpected: {repr e}"

private def testManifestAuthorityShape : IO Unit := do
  let bytes := ByteArray.mk #[1]
  let path := "modules/Bundle/Root.olean"
  let base ← mkMinimalManifest path (sha256Bytes bytes)
  let trustPolicyDigest ← fixedTrustPolicyDigest
  let trustPolicyWire ← match renderDigest trustPolicyDigest with
    | .ok value => pure value
    | .error error => throw <| IO.userError error
  expect (trustPolicyWire ==
      "sha256:68aece0ab5ed11e0010e6ba01153f01872008735add20a656c085af73a242d2c")
    "fixed trust-policy digest"
  expectManifestMalformed "foreign trust policy" { base with
      proofAbi := { base.proofAbi with trustPolicyDigest := fixedDigest 0x66 } }
    "trustPolicyDigest"
  let baseModule := base.modules.head
  expect (proofModuleOleanPathV1 baseModule.moduleName == path)
    "module path derived from qualified name"
  let wrongPathModule := { baseModule with oleanPath := "modules/Other.olean" }
  let wrongPathModules ← match NonEmptyArray.ofArray #[wrongPathModule] with
    | .ok modules => pure modules
    | .error error => throw <| IO.userError error
  expectManifestMalformed "foreign module path"
    { base with modules := wrongPathModules } "does not match moduleName"
  match proofBundleDigestV1 { base with modules := wrongPathModules } with
  | .ok _ => throw <| IO.userError "invalid manifest must not have a bundle digest"
  | .error (.malformed _) => pure ()
  | .error error => throw <| IO.userError s!"digest validation: {repr error}"

  let decomposedName := String.ofList [Char.ofNat 0x65, Char.ofNat 0x0301]
  let decomposedExport := { base.exports.head with invariantName := decomposedName }
  let decomposedExports ← match NonEmptyArray.ofArray #[decomposedExport] with
    | .ok exports => pure exports
    | .error error => throw <| IO.userError error
  let decomposedManifest := { base with exports := decomposedExports }
  expectManifestMalformed "non-NFC invariant name" decomposedManifest
    "export.invariantName"
  let decomposedBytes ← encodeManifestBytes decomposedManifest
  match decodeProofBundleManifestV1 decomposedBytes with
  | .ok _ => throw <| IO.userError "decoded non-NFC invariant name must fail"
  | .error (.malformed detail) =>
      expect (detail.contains "export.invariantName") s!"detail={detail}"
  | .error error => throw <| IO.userError s!"decode validation: {repr error}"

  let missingRoot ← qn #["Bundle", "Missing"]
  let missingRoots ← match NonEmptyArray.ofArray #[missingRoot] with
    | .ok roots => pure roots
    | .error error => throw <| IO.userError error
  expectManifestMalformed "missing root" { base with roots := missingRoots }
    "root not present"

  let imported ← qn #["Trusted", "Base"]
  let duplicateImportModule := { baseModule with imports := #[imported, imported] }
  let duplicateImportModules ← match NonEmptyArray.ofArray #[duplicateImportModule] with
    | .ok modules => pure modules
    | .error error => throw <| IO.userError error
  expectManifestMalformed "duplicate import"
    { base with modules := duplicateImportModules } "duplicate module import"

  let firstName ← qn #["Bundle", "A"]
  let secondName ← qn #["Bundle", "B"]
  let firstModule := { baseModule with
    moduleName := firstName
    oleanPath := proofModuleOleanPathV1 firstName }
  let secondModule := { baseModule with
    moduleName := secondName
    oleanPath := proofModuleOleanPathV1 secondName }
  let reversedModules ← match NonEmptyArray.ofArray #[secondModule, firstModule] with
    | .ok modules => pure modules
    | .error error => throw <| IO.userError error
  let firstRoots ← match NonEmptyArray.ofArray #[firstName] with
    | .ok roots => pure roots
    | .error error => throw <| IO.userError error
  let baseExport := base.exports.head
  let firstExport := { baseExport with ownerModule := firstName }
  let firstExports ← match NonEmptyArray.ofArray #[firstExport] with
    | .ok exports => pure exports
    | .error error => throw <| IO.userError error
  expectManifestMalformed "module order" { base with
      modules := reversedModules, roots := firstRoots, exports := firstExports }
    "strictly sorted by moduleName"

  let zExport := { firstExport with invariantName := "z" }
  let aExport := { firstExport with invariantName := "a" }
  let reversedExports ← match NonEmptyArray.ofArray #[zExport, aExport] with
    | .ok exports => pure exports
    | .error error => throw <| IO.userError error
  let sortedModules ← match NonEmptyArray.ofArray #[firstModule, secondModule] with
    | .ok modules => pure modules
    | .error error => throw <| IO.userError error
  expectManifestValid "canonical authority shape" { base with
    modules := sortedModules, roots := firstRoots, exports := firstExports }

  let reversedRoots ← match NonEmptyArray.ofArray #[secondName, firstName] with
    | .ok roots => pure roots
    | .error error => throw <| IO.userError error
  expectManifestMalformed "root order" { base with
      modules := sortedModules, roots := reversedRoots, exports := firstExports }
    "strictly sorted"

  -- Direct `.olean` import order is authoritative and must not be sorted.
  let zImport ← qn #["Trusted", "Z"]
  let aImport ← qn #["Trusted", "A"]
  let orderedImportModule := { firstModule with imports := #[zImport, aImport] }
  let orderedImportModules ← match
      NonEmptyArray.ofArray #[orderedImportModule, secondModule] with
    | .ok modules => pure modules
    | .error error => throw <| IO.userError error
  expectManifestValid "direct import order preserved" { base with
    modules := orderedImportModules, roots := firstRoots, exports := firstExports }

  expectManifestMalformed "export order" { base with
      modules := sortedModules, roots := firstRoots, exports := reversedExports }
    "strictly sorted by invariantName"

  -- Qualified names compare component-by-component, not by dot-joined text:
  -- `["a", "z"]` sorts before `["a'"]` because `"a"` is a byte prefix.
  let prefixName ← qn #["a", "z"]
  let apostropheName ← qn #["a'"]
  let prefixModule := { baseModule with
    moduleName := prefixName
    oleanPath := proofModuleOleanPathV1 prefixName }
  let apostropheModule := { baseModule with
    moduleName := apostropheName
    oleanPath := proofModuleOleanPathV1 apostropheName }
  let componentOrderedModules ← match
      NonEmptyArray.ofArray #[prefixModule, apostropheModule] with
    | .ok modules => pure modules
    | .error error => throw <| IO.userError error
  let componentOrderedRoots ← match
      NonEmptyArray.ofArray #[prefixName, apostropheName] with
    | .ok roots => pure roots
    | .error error => throw <| IO.userError error
  let prefixExport := { baseExport with theoremName := prefixName, ownerModule := prefixName }
  let apostropheExport := {
    baseExport with theoremName := apostropheName, ownerModule := apostropheName }
  let componentOrderedExports ← match
      NonEmptyArray.ofArray #[prefixExport, apostropheExport] with
    | .ok exports => pure exports
    | .error error => throw <| IO.userError error
  expectManifestValid "component-wise UTF-8 authority order" { base with
    modules := componentOrderedModules
    roots := componentOrderedRoots
    exports := componentOrderedExports }

unsafe def run : IO Unit := do
  testOpenWellFormed
  testWrongSchema
  testNonCanonicalJcs
  testOleanDigestMismatch
  testMissingModule
  testExtraModule
  testManifestAuthorityShape
  testDeclaredLoadPlansAndCycles
  IO.println "Tests.Semantic.ProofBundleV1: ok"

end Tests.Semantic.ProofBundleV1
