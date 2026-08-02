import ProofForgeV2.Compiler.ProofBundleFilesV1
import ProofForgeV2.Core.Common

namespace Tests.Compiler.ProofBundleFilesV1

open ProofForgeV2.Compiler.ProofBundleFilesV1
open ProofForgeV2.Core.Common
open ProofForgeV2.Semantic.ProofBundleV1
open System

private def expect (condition : Bool) (message : String) : IO Unit := do
  unless condition do throw <| IO.userError message

private def runTool (command : String) (args : Array String) : IO Unit := do
  let output ← IO.Process.output {
    cmd := command
    args
    stdin := .null
    stdout := .piped
    stderr := .piped
    inheritEnv := false
  }
  unless output.exitCode == 0 do
    throw <| IO.userError s!"{command} failed: {output.stderr}"

private def qn (components : Array String) : IO QualifiedName :=
  match parseQualifiedName components with
  | .ok value => pure value
  | .error error => throw <| IO.userError error

private def digest (tag : UInt8) : Digest :=
  sha256Bytes (ByteArray.mk #[tag, 1, 2, 3])

private def manifest (path : String) (contents : ByteArray) : IO ProofBundleManifestV1 := do
  let moduleName ← qn #["Bundle", "Root"]
  let abiModuleName ← qn proofAbiModuleComponentsV1
  let theoremName ← qn proofAbiTheoremComponentsV1
  let moduleRow : ProofModuleV1 := {
    moduleName, oleanPath := path, oleanDigest := sha256Bytes contents, imports := #[] }
  let exportRow : ProofExportV1 := {
    invariantName := "truth", invariantOrdinal := 0, theoremName, ownerModule := moduleName }
  let modules ← match NonEmptyArray.ofArray #[moduleRow] with
    | .ok value => pure value
    | .error error => throw <| IO.userError error
  let exports ← match NonEmptyArray.ofArray #[exportRow] with
    | .ok value => pure value
    | .error error => throw <| IO.userError error
  let roots ← match NonEmptyArray.ofArray #[moduleName] with
    | .ok value => pure value
    | .error error => throw <| IO.userError error
  pure {
    schema := proofBundleSchemaV1
    sourceHash := digest 0x11
    semanticHash := digest 0x22
    semanticProvenanceDigest := digest 0x33
    toolchainLockDigest := digest 0x44
    proofAbi := {
      semanticSchema := proofAbiSemanticSchemaV1
      moduleName := abiModuleName
      theoremName
      abiOleanDigest := digest 0x55
      trustPolicyDigest := digest 0x66
      trustedBaseClosureDigest := digest 0x77 }
    roots, modules, exports }

private def manifestBytes (path : String) (contents : ByteArray) : IO ByteArray := do
  match encodeProofBundleManifestV1 (← manifest path contents) with
  | .ok text => pure text.toUTF8
  | .error error => throw <| IO.userError s!"manifest encode: {repr error}"

private def reset (root : FilePath) : IO FilePath := do
  try IO.FS.removeDirAll root catch _ => pure ()
  IO.FS.createDirAll root
  IO.FS.realPath root

private def writeBundle (root : FilePath) (path : String) (contents : ByteArray) : IO Unit := do
  let target := root / FilePath.mk path
  let parent ← match target.parent with
    | some value => pure value
    | none => throw <| IO.userError "module path has no parent"
  IO.FS.createDirAll parent
  IO.FS.writeBinFile target contents
  IO.FS.writeBinFile (root / proofBundleManifestFileNameV1) (← manifestBytes path contents)

private def failed (result : Except ProofBundleFilesErrorV1 OpenedProofBundleV1) : Bool :=
  match result with | .error _ => true | .ok _ => false

private def expectFilesystem (label : String) (root : FilePath) : IO Unit := do
  expect (failed (← loadProofBundleFilesV1 root)) s!"{label}: unexpectedly accepted"

private def testPositiveAndRootPolicy (base : FilePath) : IO Unit := do
  let contents := "nested-olean".toUTF8
  let path := "modules/Bundle/Root.olean"
  let root ← reset (base / "positive")
  writeBundle root path contents
  match ← loadProofBundleFilesV1 root with
  | .ok opened => expect (opened.moduleFiles.size == 1) "positive nested module count"
  | .error error => throw <| IO.userError s!"positive nested bundle: {repr error}"
  expect (match ← loadProofBundleFilesV1 (FilePath.mk "relative") with
    | .error .invalidRoot => true | _ => false) "relative root rejected"
  expect (match ← loadProofBundleFilesV1 (FilePath.mk (root.toString ++ "\x00tail")) with
    | .error .invalidRoot => true | _ => false) "NUL root rejected"
  let link := base / "root-link"
  try IO.FS.removeFile link catch _ => pure ()
  runTool "/bin/ln" #["-s", root.toString, link.toString]
  expectFilesystem "root symlink" link

private def testManifestKinds (base : FilePath) : IO Unit := do
  let path := "modules/Root.olean"
  let contents := "olean".toUTF8
  let root ← reset (base / "manifest-missing")
  IO.FS.createDirAll (root / "modules")
  IO.FS.writeBinFile (root / FilePath.mk path) contents
  expectFilesystem "manifest missing" root
  let root ← reset (base / "manifest-symlink")
  writeBundle root path contents
  IO.FS.rename (root / proofBundleManifestFileNameV1) (root / "alternate")
  runTool "/bin/ln" #["-s", "alternate", (root / proofBundleManifestFileNameV1).toString]
  expectFilesystem "manifest symlink" root
  let root ← reset (base / "manifest-hardlink")
  writeBundle root path contents
  runTool "/bin/ln" #[(root / proofBundleManifestFileNameV1).toString,
    (root / "manifest-copy").toString]
  expectFilesystem "manifest hardlink" root
  for kind in #["directory", "fifo"] do
    let root ← reset (base / s!"manifest-{kind}")
    IO.FS.createDirAll (root / "modules")
    IO.FS.writeBinFile (root / FilePath.mk path) contents
    if kind == "directory" then IO.FS.createDirAll (root / proofBundleManifestFileNameV1)
    else runTool "/usr/bin/mkfifo" #[(root / proofBundleManifestFileNameV1).toString]
    expectFilesystem s!"manifest {kind}" root

private def testModuleKinds (base : FilePath) : IO Unit := do
  let path := "modules/Bundle/Root.olean"
  let contents := "olean".toUTF8
  let root ← reset (base / "module-missing")
  writeBundle root path contents
  IO.FS.removeFile (root / FilePath.mk path)
  expectFilesystem "module missing" root
  let root ← reset (base / "module-symlink")
  writeBundle root path contents
  IO.FS.rename (root / FilePath.mk path) (root / "alternate")
  runTool "/bin/ln" #["-s", (root / "alternate").toString, (root / FilePath.mk path).toString]
  expectFilesystem "module symlink" root
  let root ← reset (base / "module-hardlink")
  writeBundle root path contents
  runTool "/bin/ln" #[(root / FilePath.mk path).toString, (root / "module-copy").toString]
  expectFilesystem "module hardlink" root
  for kind in #["directory", "fifo"] do
    let root ← reset (base / s!"module-{kind}")
    writeBundle root path contents
    IO.FS.removeFile (root / FilePath.mk path)
    if kind == "directory" then IO.FS.createDirAll (root / FilePath.mk path)
    else runTool "/usr/bin/mkfifo" #[(root / FilePath.mk path).toString]
    expectFilesystem s!"module {kind}" root

private def testExactTreeAndMalformed (base : FilePath) : IO Unit := do
  let path := "modules/Bundle/Root.olean"
  let contents := "olean".toUTF8
  let root ← reset (base / "extra-root")
  writeBundle root path contents
  IO.FS.writeBinFile (root / "extra") ByteArray.empty
  expectFilesystem "extra root file" root
  let root ← reset (base / "extra-module")
  writeBundle root path contents
  IO.FS.writeBinFile (root / "modules/extra") ByteArray.empty
  expectFilesystem "extra module file" root
  let root ← reset (base / "extra-nested-file")
  writeBundle root path contents
  IO.FS.writeBinFile (root / "modules/Bundle/extra") ByteArray.empty
  expectFilesystem "extra nested file" root
  let root ← reset (base / "extra-nested-directory")
  writeBundle root path contents
  IO.FS.createDirAll (root / "modules/Bundle/extra")
  expectFilesystem "extra nested directory" root
  let root ← reset (base / "malformed")
  IO.FS.writeBinFile (root / proofBundleManifestFileNameV1) "{".toUTF8
  expect (match ← loadProofBundleFilesV1 root with
    | .error (.bundle _) => true | _ => false) "malformed manifest delegates to bundle authority"
  let root ← reset (base / "invalid-relative")
  IO.FS.writeBinFile (root / proofBundleManifestFileNameV1)
    "{\"schema\":\"pf.proof-bundle.v1\",\"modules\":[{\"oleanPath\":\"../bad.olean\"}]}".toUTF8
  expect (match ← loadProofBundleFilesV1 root with
    | .error (.bundle _) => true | _ => false) "invalid relative module path rejected by decoder"
  let root ← reset (base / "nul-path")
  IO.FS.writeBinFile (root / proofBundleManifestFileNameV1)
    "{\"schema\":\"pf.proof-bundle.v1\",\"modules\":[{\"oleanPath\":\"modules/\\u0000.olean\"}]}".toUTF8
  expect (match ← loadProofBundleFilesV1 root with
    | .error (.bundle _) => true | _ => false) "NUL module path rejected by decoder"

unsafe def run : IO Unit := do
  let base ← reset ((← IO.currentDir) / "build/proof-bundle-files-v1")
  testPositiveAndRootPolicy base
  testManifestKinds base
  testModuleKinds base
  testExactTreeAndMalformed base
  IO.println "Tests.Compiler.ProofBundleFilesV1: ok"

end Tests.Compiler.ProofBundleFilesV1
