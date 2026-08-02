import ProofForgeV2.Core.Common
import ProofForgeV2.Core.Canonical

/-
  ProofForgeV2.Semantic.ProofBundleV1 — engineering in-memory validation for
  ProofBundleV1-shaped manifests and supplied module maps (R-3 foundation).

  Scope (engineering, not formal TST-PROOF-001 / Stage-0 / contained worker):
    * PF-JCS manifest parse + re-encode identity
    * closed schema / proofAbi identity strings
    * nonempty roots/modules/exports, unique module names & olean paths
    * proofBundleDigest = SHA-256("proof-forge.proof-bundle.v1" || 0x00 || JCS)
    * each module's oleanDigest must equal SHA-256 of supplied file bytes
    * fail closed on wrong schema, missing module file, digest mismatch,
      non-canonical JCS, empty tables, unknown top-level keys

  Out of scope this slice:
    * filesystem safe loading / contained worker / empty LEAN_PATH / dirfd open
    * trust-policy axiom graph / ambient olean search
    * ToolLock digest join / product check-build wiring
    * formal evidence ceremony
-/

namespace ProofForgeV2.Semantic.ProofBundleV1

open ProofForgeV2.Core.Common

/-- Wire schema for the proof-bundle manifest. -/
def proofBundleSchemaV1 : String := "proof-forge.proof-bundle.v1"

/-- Semantic-program schema expected on proofAbi.semanticSchema. -/
def proofAbiSemanticSchemaV1 : String := "proof-forge.semantic-program.v1"

/-- Exact ABI module name components (SPEC-SEM-CORE). -/
def proofAbiModuleComponentsV1 : Array String :=
  #["ProofForgeV2", "Semantic", "InvariantABI"]

/-- Exact theorem name components (SPEC-SEM-CORE). -/
def proofAbiTheoremComponentsV1 : Array String :=
  #["ProofForgeV2", "Semantic", "InvariantABI", "InvariantTheoremV1"]

/-- Closed load/validation errors (engineering). -/
inductive ProofBundleErrorV1 where
  | malformed (detail : String)
  | digestMismatch (detail : String)
  | missingModule (path : String)
  | extraModule (path : String)
  | internal (detail : String)
  deriving BEq, Repr

private def err (e : ProofBundleErrorV1) : Except ProofBundleErrorV1 α :=
  .error e

/-- Engineering proofAbi identity (digest fields required as exact wire strings). -/
structure ProofAbiIdentityV1 where
  semanticSchema : String
  moduleName : QualifiedName
  theoremName : QualifiedName
  abiOleanDigest : Digest
  trustPolicyDigest : Digest
  trustedBaseClosureDigest : Digest

structure ProofModuleV1 where
  moduleName : QualifiedName
  oleanPath : String
  oleanDigest : Digest
  imports : Array QualifiedName

structure ProofExportV1 where
  invariantName : String
  invariantOrdinal : UInt32
  theoremName : QualifiedName
  ownerModule : QualifiedName

structure ProofBundleManifestV1 where
  schema : String
  sourceHash : Digest
  semanticHash : Digest
  semanticProvenanceDigest : Digest
  toolchainLockDigest : Digest
  proofAbi : ProofAbiIdentityV1
  roots : NonEmptyArray QualifiedName
  modules : NonEmptyArray ProofModuleV1
  exports : NonEmptyArray ProofExportV1

/-- Opened bundle: structure-validated + digest-checked modules. -/
structure OpenedProofBundleV1 where
  private mk ::
    manifest : ProofBundleManifestV1
    bundleDigest : Digest
    /-- oleanPath → verified file bytes (exact SHA-256 match). -/
    moduleFiles : Array (String × ByteArray)

/-! ### PF-JCS helpers -/

private def requireObject (value : PfJson) (context : String) :
    Except ProofBundleErrorV1 (Array (String × PfJson)) :=
  match value with
  | .object fields => pure fields
  | _ => err (.malformed s!"{context} must be a PF-JCS object")

private def fieldExact
    (fields : Array (String × PfJson)) (key : String) (context : String) :
    Except ProofBundleErrorV1 PfJson := do
  match fields.find? (fun f => f.1 == key) with
  | some (_, v) => pure v
  | none => err (.malformed s!"{context} missing field '{key}'")

private def requireExactKeys
    (fields : Array (String × PfJson)) (expected : Array String) (context : String) :
    Except ProofBundleErrorV1 Unit := do
  unless fields.size == expected.size do
    return ← err (.malformed s!"{context} must have exactly {expected.size} fields")
  let mut i : Nat := 0
  for f in fields do
    match expected[i]? with
    | none => return ← err (.malformed s!"{context} unexpected field")
    | some k =>
        unless f.1 == k do
          return ← err (.malformed s!"{context} expected key '{k}', got '{f.1}'")
    i := i + 1

private def requireString (v : PfJson) (context : String) :
    Except ProofBundleErrorV1 String :=
  match v with
  | .string s => pure s
  | _ => err (.malformed s!"{context} must be a string")

private def requireUint32 (v : PfJson) (context : String) :
    Except ProofBundleErrorV1 UInt32 :=
  match v with
  | .int n =>
      if 0 ≤ n && n ≤ Int.ofNat UInt32.size.pred then
        pure (UInt32.ofNat n.toNat)
      else
        err (.malformed s!"{context} out of UInt32 range")
  | _ => err (.malformed s!"{context} must be an integer")

private def requireDigest (v : PfJson) (context : String) :
    Except ProofBundleErrorV1 Digest := do
  let s ← requireString v context
  match parseDigest s with
  | .ok d => pure d
  | .error e => err (.malformed s!"{context}: {e}")

private def requireStringArray (v : PfJson) (context : String) :
    Except ProofBundleErrorV1 (Array String) :=
  match v with
  | .array items => do
      let mut out : Array String := #[]
      for it in items do
        let s ← requireString it context
        out := out.push s
      pure out
  | _ => err (.malformed s!"{context} must be an array of strings")

private def requireQualifiedName (v : PfJson) (context : String) :
    Except ProofBundleErrorV1 QualifiedName := do
  let comps ← requireStringArray v context
  match parseQualifiedName comps with
  | .ok qn => pure qn
  | .error e => err (.malformed s!"{context}: {e}")

private def requireQualifiedNameArray (v : PfJson) (context : String) :
    Except ProofBundleErrorV1 (Array QualifiedName) :=
  match v with
  | .array items => do
      let mut out : Array QualifiedName := #[]
      for it in items do
        let qn ← requireQualifiedName it context
        out := out.push qn
      pure out
  | _ => err (.malformed s!"{context} must be an array")

private def requireNonEmptyQualifiedNames (v : PfJson) (context : String) :
    Except ProofBundleErrorV1 (NonEmptyArray QualifiedName) := do
  let arr ← requireQualifiedNameArray v context
  match NonEmptyArray.ofArray arr with
  | .ok ne => pure ne
  | .error e => err (.malformed s!"{context}: {e}")

private def qnComponents (qn : QualifiedName) : Array String :=
  NonEmptyArray.toArray qn.components

/-- The only legal bundle-relative path for a module. Filesystem consumers
    derive this value from the validated module identity; the manifest cannot
    choose an unrelated pathname. -/
def proofModuleOleanPathV1 (moduleName : QualifiedName) : String :=
  "modules/" ++ String.intercalate "/" (qnComponents moduleName).toList ++ ".olean"

private def compareUtf8Bytes (left right : ByteArray) : Ordering :=
  let count := min left.size right.size
  let rec loop (index : Nat) : Ordering :=
    if index < count then
      if left.get! index < right.get! index then .lt
      else if left.get! index > right.get! index then .gt
      else loop (index + 1)
    else if left.size < right.size then .lt
    else if left.size > right.size then .gt
    else .eq
  loop 0

private def compareQualifiedNames (left right : QualifiedName) : Ordering :=
  let leftComponents := qnComponents left
  let rightComponents := qnComponents right
  let count := min leftComponents.size rightComponents.size
  let rec loop (index : Nat) : Ordering :=
    if index < count then
      match compareUtf8Bytes leftComponents[index]!.toUTF8 rightComponents[index]!.toUTF8 with
      | .eq => loop (index + 1)
      | order => order
    else if leftComponents.size < rightComponents.size then .lt
    else if leftComponents.size > rightComponents.size then .gt
    else .eq
  loop 0

private def compareExports (left right : ProofExportV1) : Ordering :=
  match compareUtf8Bytes left.invariantName.toUTF8 right.invariantName.toUTF8 with
  | .eq => compareQualifiedNames left.theoremName right.theoremName
  | order => order

private def qnToPfJson (qn : QualifiedName) : PfJson :=
  .array ((qnComponents qn).map PfJson.string)

private def digestToPfJson (d : Digest) : Except ProofBundleErrorV1 PfJson :=
  match renderDigest d with
  | .ok s => pure (.string s)
  | .error e => err (.internal e)

/-! ### Encode / decode -/

private def encodeProofAbi (abi : ProofAbiIdentityV1) :
    Except ProofBundleErrorV1 PfJson := do
  let abiD ← digestToPfJson abi.abiOleanDigest
  let trustD ← digestToPfJson abi.trustPolicyDigest
  let baseD ← digestToPfJson abi.trustedBaseClosureDigest
  pure (.object #[
    ("abiOleanDigest", abiD),
    ("moduleName", qnToPfJson abi.moduleName),
    ("semanticSchema", .string abi.semanticSchema),
    ("theoremName", qnToPfJson abi.theoremName),
    ("trustPolicyDigest", trustD),
    ("trustedBaseClosureDigest", baseD)
  ])

private def decodeProofAbi (v : PfJson) :
    Except ProofBundleErrorV1 ProofAbiIdentityV1 := do
  let fields ← requireObject v "proofAbi"
  requireExactKeys fields
    #["abiOleanDigest", "moduleName", "semanticSchema", "theoremName",
      "trustPolicyDigest", "trustedBaseClosureDigest"] "proofAbi"
  let abiOleanDigest ← requireDigest (← fieldExact fields "abiOleanDigest" "proofAbi") "proofAbi.abiOleanDigest"
  let moduleName ← requireQualifiedName (← fieldExact fields "moduleName" "proofAbi") "proofAbi.moduleName"
  let semanticSchema ← requireString (← fieldExact fields "semanticSchema" "proofAbi") "proofAbi.semanticSchema"
  let theoremName ← requireQualifiedName (← fieldExact fields "theoremName" "proofAbi") "proofAbi.theoremName"
  let trustPolicyDigest ← requireDigest (← fieldExact fields "trustPolicyDigest" "proofAbi") "proofAbi.trustPolicyDigest"
  let trustedBaseClosureDigest ←
    requireDigest (← fieldExact fields "trustedBaseClosureDigest" "proofAbi") "proofAbi.trustedBaseClosureDigest"
  pure {
    semanticSchema, moduleName, theoremName, abiOleanDigest,
    trustPolicyDigest, trustedBaseClosureDigest
  }

private def encodeModule (m : ProofModuleV1) :
    Except ProofBundleErrorV1 PfJson := do
  let dig ← digestToPfJson m.oleanDigest
  let importsJson := .array (m.imports.map qnToPfJson)
  pure (.object #[
    ("imports", importsJson),
    ("moduleName", qnToPfJson m.moduleName),
    ("oleanDigest", dig),
    ("oleanPath", .string m.oleanPath)
  ])

private def decodeModule (v : PfJson) :
    Except ProofBundleErrorV1 ProofModuleV1 := do
  let fields ← requireObject v "module"
  requireExactKeys fields
    #["imports", "moduleName", "oleanDigest", "oleanPath"] "module"
  let imports ← requireQualifiedNameArray (← fieldExact fields "imports" "module") "module.imports"
  let moduleName ← requireQualifiedName (← fieldExact fields "moduleName" "module") "module.moduleName"
  let oleanDigest ← requireDigest (← fieldExact fields "oleanDigest" "module") "module.oleanDigest"
  let oleanPath ← requireString (← fieldExact fields "oleanPath" "module") "module.oleanPath"
  match parseProjectRelativePath oleanPath with
  | .ok _ => pure ()
  | .error e => return ← err (.malformed s!"module.oleanPath: {e}")
  pure { moduleName, oleanPath, oleanDigest, imports }

private def encodeExport (e : ProofExportV1) :
    Except ProofBundleErrorV1 PfJson := do
  pure (.object #[
    ("invariantName", .string e.invariantName),
    ("invariantOrdinal", .int (Int.ofNat e.invariantOrdinal.toNat)),
    ("ownerModule", qnToPfJson e.ownerModule),
    ("theoremName", qnToPfJson e.theoremName)
  ])

private def decodeExport (v : PfJson) :
    Except ProofBundleErrorV1 ProofExportV1 := do
  let fields ← requireObject v "export"
  requireExactKeys fields
    #["invariantName", "invariantOrdinal", "ownerModule", "theoremName"] "export"
  let invariantName ← requireString (← fieldExact fields "invariantName" "export") "export.invariantName"
  let invariantOrdinal ← requireUint32 (← fieldExact fields "invariantOrdinal" "export") "export.invariantOrdinal"
  let ownerModule ← requireQualifiedName (← fieldExact fields "ownerModule" "export") "export.ownerModule"
  let theoremName ← requireQualifiedName (← fieldExact fields "theoremName" "export") "export.theoremName"
  unless 1 ≤ invariantName.utf8ByteSize && invariantName.utf8ByteSize ≤ 240 do
    return ← err (.malformed "export.invariantName length out of range")
  pure { invariantName, invariantOrdinal, theoremName, ownerModule }

/-- Encode a manifest to PF-JCS (keys sorted by renderer). -/
def encodeProofBundleManifestV1 (m : ProofBundleManifestV1) :
    Except ProofBundleErrorV1 String := do
  let src ← digestToPfJson m.sourceHash
  let sem ← digestToPfJson m.semanticHash
  let prov ← digestToPfJson m.semanticProvenanceDigest
  let tool ← digestToPfJson m.toolchainLockDigest
  let abi ← encodeProofAbi m.proofAbi
  let rootsJson := .array ((NonEmptyArray.toArray m.roots).map qnToPfJson)
  let modulesArr ← (NonEmptyArray.toArray m.modules).mapM encodeModule
  let exportsArr ← (NonEmptyArray.toArray m.exports).mapM encodeExport
  let obj := PfJson.object #[
    ("exports", .array exportsArr),
    ("modules", .array modulesArr),
    ("proofAbi", abi),
    ("roots", rootsJson),
    ("schema", .string m.schema),
    ("semanticHash", sem),
    ("semanticProvenanceDigest", prov),
    ("sourceHash", src),
    ("toolchainLockDigest", tool)
  ]
  match renderPfJcs obj with
  | .ok s => pure s
  | .error e => err (.internal e)

private def decodeManifestObject (fields : Array (String × PfJson)) :
    Except ProofBundleErrorV1 ProofBundleManifestV1 := do
  requireExactKeys fields
    #["exports", "modules", "proofAbi", "roots", "schema", "semanticHash",
      "semanticProvenanceDigest", "sourceHash", "toolchainLockDigest"]
    "manifest"
  let exportsV ← fieldExact fields "exports" "manifest"
  let modulesV ← fieldExact fields "modules" "manifest"
  let proofAbi ← decodeProofAbi (← fieldExact fields "proofAbi" "manifest")
  let roots ← requireNonEmptyQualifiedNames (← fieldExact fields "roots" "manifest") "manifest.roots"
  let schema ← requireString (← fieldExact fields "schema" "manifest") "manifest.schema"
  let semanticHash ← requireDigest (← fieldExact fields "semanticHash" "manifest") "manifest.semanticHash"
  let semanticProvenanceDigest ←
    requireDigest (← fieldExact fields "semanticProvenanceDigest" "manifest")
      "manifest.semanticProvenanceDigest"
  let sourceHash ← requireDigest (← fieldExact fields "sourceHash" "manifest") "manifest.sourceHash"
  let toolchainLockDigest ←
    requireDigest (← fieldExact fields "toolchainLockDigest" "manifest")
      "manifest.toolchainLockDigest"
  let modulesArr ← match modulesV with
    | .array items => do
        let mut out : Array ProofModuleV1 := #[]
        for it in items do
          out := out.push (← decodeModule it)
        pure out
    | _ => err (.malformed "manifest.modules must be an array")
  let modules ← match NonEmptyArray.ofArray modulesArr with
    | .ok ne => pure ne
    | .error e => err (.malformed s!"manifest.modules: {e}")
  let exportsArr ← match exportsV with
    | .array items => do
        let mut out : Array ProofExportV1 := #[]
        for it in items do
          out := out.push (← decodeExport it)
        pure out
    | _ => err (.malformed "manifest.exports must be an array")
  let exports ← match NonEmptyArray.ofArray exportsArr with
    | .ok ne => pure ne
    | .error e => err (.malformed s!"manifest.exports: {e}")
  pure {
    schema, sourceHash, semanticHash, semanticProvenanceDigest,
    toolchainLockDigest, proofAbi, roots, modules, exports
  }

/-- Structural validation after decode (identity + uniqueness). -/
def validateProofBundleManifestV1 (m : ProofBundleManifestV1) :
    Except ProofBundleErrorV1 Unit := do
  let validateName (name : QualifiedName) (context : String) :
      Except ProofBundleErrorV1 Unit :=
    match validateQualifiedName name with
    | .ok () => pure ()
    | .error e => err (.malformed s!"{context}: {e}")
  unless m.schema == proofBundleSchemaV1 do
    return ← err (.malformed s!"schema must be '{proofBundleSchemaV1}'")
  unless m.proofAbi.semanticSchema == proofAbiSemanticSchemaV1 do
    return ← err (.malformed s!"proofAbi.semanticSchema must be '{proofAbiSemanticSchemaV1}'")
  validateName m.proofAbi.moduleName "proofAbi.moduleName"
  validateName m.proofAbi.theoremName "proofAbi.theoremName"
  unless qnComponents m.proofAbi.moduleName == proofAbiModuleComponentsV1 do
    return ← err (.malformed "proofAbi.moduleName must be ProofForgeV2.Semantic.InvariantABI")
  unless qnComponents m.proofAbi.theoremName == proofAbiTheoremComponentsV1 do
    return ← err (.malformed "proofAbi.theoremName must be InvariantTheoremV1 FQ")
  -- Module order is the authority order used by the later exact filesystem
  -- map and importer. Strict order also supplies uniqueness.
  let mods := NonEmptyArray.toArray m.modules
  unless mods.size ≤ 1024 do
    return ← err (.malformed "manifest.modules exceeds 1024 entries")
  let mut previousModule : Option QualifiedName := none
  for mod in mods do
    validateName mod.moduleName "module.moduleName"
    match validateProjectRelativePath { value := mod.oleanPath } with
    | .ok () => pure ()
    | .error e => return ← err (.malformed s!"module.oleanPath: {e}")
    unless mod.oleanPath == proofModuleOleanPathV1 mod.moduleName do
      return ← err (.malformed "module.oleanPath does not match moduleName")
    match previousModule with
    | some previous =>
      unless compareQualifiedNames previous mod.moduleName == .lt do
        return ← err (.malformed "manifest.modules must be strictly sorted by moduleName")
    | none => pure ()
    previousModule := some mod.moduleName
    -- Direct-import order is part of the `.olean` identity and is preserved;
    -- only uniqueness is enforced here. Resolution may target another bundle
    -- module or the separately validated trusted base closure.
    let mut seenImports : Array (Array String) := #[]
    for imported in mod.imports do
      validateName imported "module.imports"
      let components := qnComponents imported
      if seenImports.any (· == components) then
        return ← err (.malformed "duplicate module import")
      seenImports := seenImports.push components
  -- Roots are a strictly sorted, unique subset of bundle modules.
  let roots := NonEmptyArray.toArray m.roots
  let mut previousRoot : Option QualifiedName := none
  for root in roots do
    validateName root "manifest.roots"
    unless mods.any (fun mod => qnComponents mod.moduleName == qnComponents root) do
      return ← err (.malformed "manifest root not present in modules")
    match previousRoot with
    | some previous =>
      unless compareQualifiedNames previous root == .lt do
        return ← err (.malformed "manifest.roots must be strictly sorted")
    | none => pure ()
    previousRoot := some root
  -- Every export ownerModule must appear in modules.
  let exports := NonEmptyArray.toArray m.exports
  let mut previousExport : Option ProofExportV1 := none
  for ex in exports do
    match validateIdentifierComponent ex.invariantName with
    | .ok () => pure ()
    | .error e => return ← err (.malformed s!"export.invariantName: {e}")
    validateName ex.theoremName "export.theoremName"
    validateName ex.ownerModule "export.ownerModule"
    let owner := qnComponents ex.ownerModule
    unless mods.any (fun m => qnComponents m.moduleName == owner) do
      return ← err (.malformed "export.ownerModule not present in modules")
    match previousExport with
    | some previous =>
      unless compareExports previous ex == .lt do
        return ← err (.malformed
          "manifest.exports must be strictly sorted by invariantName/theoremName")
    | none => pure ()
    previousExport := some ex
  pure ()

/-- Parse PF-JCS bytes with re-encode identity, then structure-validate. -/
def decodeProofBundleManifestV1 (bytes : ByteArray) :
    Except ProofBundleErrorV1 ProofBundleManifestV1 := do
  let text ← match String.fromUTF8? bytes with
    | some s => pure s
    | none => err (.malformed "manifest is not valid UTF-8")
  let value ← match parsePfJcs text with
    | .ok v => pure v
    | .error e => err (.malformed s!"PF-JCS parse: {e}")
  -- Re-encode identity (non-canonical spelling fail closed).
  match renderPfJcs value with
  | .error e => err (.malformed s!"PF-JCS re-encode: {e}")
  | .ok re =>
      unless re == text do
        return ← err (.malformed "manifest is not PF-JCS canonical")
  let fields ← requireObject value "manifest"
  let m ← decodeManifestObject fields
  validateProofBundleManifestV1 m
  pure m

/-- Domain-separated bundle digest over exact canonical JCS UTF-8. -/
def proofBundleDigestV1 (m : ProofBundleManifestV1) :
    Except ProofBundleErrorV1 Digest := do
  validateProofBundleManifestV1 m
  let jcs ← encodeProofBundleManifestV1 m
  match domainSeparatedSha256 proofBundleSchemaV1 jcs.toUTF8 with
  | .ok d => pure d
  | .error e => err (.internal e)

/-- Open a bundle from manifest bytes + supplied module file map.

    `moduleFiles` is an array of `(oleanPath, fileBytes)`. Every manifest
    module path must appear exactly once; no extra paths are allowed. -/
def openProofBundleV1
    (manifestBytes : ByteArray)
    (moduleFiles : Array (String × ByteArray)) :
    Except ProofBundleErrorV1 OpenedProofBundleV1 := do
  let m ← decodeProofBundleManifestV1 manifestBytes
  let digest ← proofBundleDigestV1 m
  -- Index supplied files (reject duplicate paths in the map).
  let mut seenPaths : Array String := #[]
  for (path, _) in moduleFiles do
    if seenPaths.any (· == path) then
      return ← err (.malformed s!"duplicate supplied module path '{path}'")
    seenPaths := seenPaths.push path
  -- Every manifest module must match supplied bytes.
  let mut verified : Array (String × ByteArray) := #[]
  for mod in NonEmptyArray.toArray m.modules do
    match moduleFiles.find? (fun p => p.1 == mod.oleanPath) with
    | none => return ← err (.missingModule mod.oleanPath)
    | some (_, bytes) =>
        let actual := sha256Bytes bytes
        unless actual.bytes == mod.oleanDigest.bytes do
          return ← err (.digestMismatch
            s!"oleanDigest mismatch for '{mod.oleanPath}'")
        verified := verified.push (mod.oleanPath, bytes)
  -- No extra files beyond the manifest.
  for (path, _) in moduleFiles do
    unless (NonEmptyArray.toArray m.modules).any (fun mod => mod.oleanPath == path) do
      return ← err (.extraModule path)
  pure ⟨m, digest, verified⟩

end ProofForgeV2.Semantic.ProofBundleV1
