import ProofForgeV2.Semantic.ProofBundleV1

/-! Compiler-owned, no-follow filesystem adapter for ProofBundleV1.

The native side owns filesystem policy only.  The two semantic authorities are
`decodeProofBundleManifestV1` (to derive paths) and `openProofBundleV1` (final
decode, validation, and digest joins). -/

namespace ProofForgeV2.Compiler.ProofBundleFilesV1

open ProofForgeV2.Semantic.ProofBundleV1
open System

def proofBundleManifestFileNameV1 : String := "proof-bundle.json"

inductive ProofBundleFilesErrorV1 where
  | invalidRoot
  | filesystem (detail : String)
  | bundle (error : ProofBundleErrorV1)
  deriving Repr

@[extern "proof_forge_read_proof_bundle_manifest_v1"]
private opaque nativeReadManifestV1 (root : @& String) : IO (Except String ByteArray)

@[extern "proof_forge_read_proof_bundle_files_v1"]
private opaque nativeReadFilesV1 (root : @& String) (paths : @& Array String) :
  IO (Except String (ByteArray × Array ByteArray))

private def containsNul (value : String) : Bool := value.toList.any (· == '\x00')

/-- Load the fixed manifest and exactly its canonical module path trie.  The
second native operation rereads the manifest under the same full safety policy;
byte inequality rejects replacement between protocol phases. -/
def loadProofBundleFilesV1 (root : FilePath) :
    IO (Except ProofBundleFilesErrorV1 OpenedProofBundleV1) := do
  let rootString := root.toString
  if !root.isAbsolute || rootString.isEmpty || containsNul rootString then
    return .error .invalidRoot
  let first ← nativeReadManifestV1 rootString
  let firstBytes ← match first with
    | .error e => return .error (.filesystem e)
    | .ok bytes => pure bytes
  let manifest ← match decodeProofBundleManifestV1 firstBytes with
    | .error e => return .error (.bundle e)
    | .ok manifest => pure manifest
  let paths := manifest.modules.toArray.map (·.oleanPath)
  let second ← nativeReadFilesV1 rootString paths
  let (secondBytes, moduleBytes) ← match second with
    | .error e => return .error (.filesystem e)
    | .ok pair => pure pair
  unless secondBytes == firstBytes do
    return .error (.filesystem "manifest:changed-between-phases")
  unless moduleBytes.size == paths.size do
    return .error (.filesystem "native-protocol")
  match openProofBundleV1 secondBytes (paths.zip moduleBytes) with
  | .error e => pure (.error (.bundle e))
  | .ok opened => pure (.ok opened)

end ProofForgeV2.Compiler.ProofBundleFilesV1
