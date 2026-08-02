/-
  Engineering artifact content / exact disk-closure authority (D3-E7 commit 1/2).

  Sole leaf for closed artifact roles, path claims, content descriptors, and the
  unique no-follow directory scanner/walker. Produces a private-ctor inventory
  of role/path/size/contentSha256 for materialized-base and finalized-extra
  leaves. Fixed auxiliary leaves (this stage: evidence.json / manifest.json)
  participate in exact closure and byte caps but never enter the inventory.

  Engineering static/stable observation only:
  - before/readBinFile/after `symlinkMetadata` checks (type, numLinks, byteSize)
  - no retained fd across the read; no TOCTOU / containment / race-free claim
  - not formal OutputSetV1 / hermetic publisher / supervisor

  Must not import OutputSetV1, EngineeringFinalizationV1, or
  EngineeringDiskClosureV1 (those adapt over this leaf).
-/
import ProofForgeV2.Materialization.MaterializedArtifactsV1
import ProofForgeV2.Core.Common

namespace ProofForgeV2

open ProofForgeV2.Core.Common
open System

/-! ## Resource caps (sole definitions; EngineeringDiskClosure re-exports) -/

/-- Max regular files in a published engineering closure (incl. aux sidecars). -/
def maxEngineeringDiskClosureFilesV1 : Nat := 1024

/-- Max bytes per regular file (metadata + read size). -/
def maxEngineeringDiskClosureFileBytesV1 : Nat := 64 * 1024 * 1024

/-- Max total bytes across all regular files in the closure (artifacts + aux). -/
def maxEngineeringDiskClosureTotalBytesV1 : Nat := 256 * 1024 * 1024

/-- Slack entries beyond exact expected direct children before PF-OUTPUT-LIMIT. -/
def maxEngineeringDiskClosureDirEntrySlackV1 : Nat := 8

/-- Fixed transitional evidence sidecar name (aux; not in artifact inventory). -/
def evidenceSidecarNameV1 : String := "evidence.json"

/-- Fixed transitional manifest sidecar name (aux; not in artifact inventory). -/
def manifestSidecarNameV1 : String := "manifest.json"

/-! ## Closed role -/

/-- Closed artifact content role (exact wire + rank). Only two product roles. -/
inductive ArtifactContentRoleV1 where
  | materializedBase
  | finalizedExtra
  deriving DecidableEq, Repr, BEq

namespace ArtifactContentRoleV1

/-- Exact wire identity for the closed role. -/
def toWire : ArtifactContentRoleV1 → String
  | .materializedBase => "materialized-base"
  | .finalizedExtra => "finalized-extra"

/-- Canonical rank: base before extra. -/
def rank : ArtifactContentRoleV1 → Nat
  | .materializedBase => 0
  | .finalizedExtra => 1

/-- Parse exact wire; reject unknown. -/
def ofWire? : String → Option ArtifactContentRoleV1
  | "materialized-base" => some .materializedBase
  | "finalized-extra" => some .finalizedExtra
  | _ => none

end ArtifactContentRoleV1

/-! ## Path claim / content descriptor / inventory -/

/-- Path claim before physical scan (role + relative path). -/
structure ArtifactPathClaimV1 where
  role : ArtifactContentRoleV1
  path : String
  deriving DecidableEq, Repr, BEq

/-- Observed artifact content descriptor after stable read + SHA-256. -/
structure ArtifactContentDescriptorV1 where
  role : ArtifactContentRoleV1
  path : String
  size : Nat
  contentSha256 : Digest
  deriving Repr

namespace ArtifactContentDescriptorV1

/-- Exact field equality (digest by algorithm + raw bytes). -/
def beq (a b : ArtifactContentDescriptorV1) : Bool :=
  a.role == b.role &&
  a.path == b.path &&
  a.size == b.size &&
  a.contentSha256.algorithm == b.contentSha256.algorithm &&
  a.contentSha256.bytes == b.contentSha256.bytes

instance : BEq ArtifactContentDescriptorV1 := ⟨beq⟩

end ArtifactContentDescriptorV1

/-- Private-ctor inventory of artifact content descriptors (aux excluded). -/
structure ArtifactContentInventoryV1 where
  private mk ::
  descriptors : Array ArtifactContentDescriptorV1

namespace ArtifactContentInventoryV1

def descriptorsOf (inv : ArtifactContentInventoryV1) : Array ArtifactContentDescriptorV1 :=
  inv.descriptors

def size (inv : ArtifactContentInventoryV1) : Nat := inv.descriptors.size

/-- Exact inventory equality. -/
def beq (a b : ArtifactContentInventoryV1) : Bool :=
  if a.descriptors.size != b.descriptors.size then false
  else Id.run do
    let mut ok := true
    for pair in a.descriptors.zip b.descriptors do
      unless ArtifactContentDescriptorV1.beq pair.1 pair.2 do
        ok := false
    pure ok

instance : BEq ArtifactContentInventoryV1 := ⟨beq⟩

end ArtifactContentInventoryV1

/-! ## Canonical order helpers -/

/-- Strict less-than on role-rank then UTF-8 path (byte-string `<`). -/
def artifactClaimLtV1 (a b : ArtifactPathClaimV1) : Bool :=
  let ra := ArtifactContentRoleV1.rank a.role
  let rb := ArtifactContentRoleV1.rank b.role
  ra < rb || (ra == rb && a.path < b.path)

/-- Strict less-than on descriptor role-rank then UTF-8 path. -/
def artifactDescriptorLtV1 (a b : ArtifactContentDescriptorV1) : Bool :=
  let ra := ArtifactContentRoleV1.rank a.role
  let rb := ArtifactContentRoleV1.rank b.role
  ra < rb || (ra == rb && a.path < b.path)

/-- Stable sort of claims by role-rank then path. -/
def sortArtifactPathClaimsV1 (claims : Array ArtifactPathClaimV1) : Array ArtifactPathClaimV1 :=
  claims.qsort artifactClaimLtV1

/-- Stable sort of descriptors by role-rank then path. -/
def sortArtifactContentDescriptorsV1
    (ds : Array ArtifactContentDescriptorV1) : Array ArtifactContentDescriptorV1 :=
  ds.qsort artifactDescriptorLtV1

/-! ## Pure validation -/

private def pathError (message : String) : IO α :=
  throw <| IO.userError s!"PF-OUTPUT-PATH: {message}"

private def limitError (message : String) : IO α :=
  throw <| IO.userError s!"PF-OUTPUT-LIMIT: {message}"

/-- Pure claim validation (IO error for shared product error surface). -/
def validateArtifactPathClaimsV1 (claims : Array ArtifactPathClaimV1) : IO Unit := do
  let mut seen : Array String := #[]
  for c in claims do
    unless safeRelativeArtifactPathV1 c.path do
      pathError s!"unsafe artifact path '{c.path}'"
    if seen.contains c.path then
      pathError s!"duplicate artifact path '{c.path}'"
    seen := seen.push c.path
  for a in claims do
    for b in claims do
      if a.path != b.path && b.path.startsWith (a.path ++ "/") then
        pathError s!"file/directory prefix conflict '{a.path}'"

/-- True when `path` collides with a fixed transitional sidecar name. -/
def isFixedSidecarPathV1 (path : String) : Bool :=
  path == evidenceSidecarNameV1 || path == manifestSidecarNameV1

/-- Validate claims against fixed aux leaf paths (sidecars + arbitrary aux). -/
def validateArtifactClaimsAgainstAuxV1
    (claims : Array ArtifactPathClaimV1) (auxiliaryLeaves : Array String) : IO (Array String) := do
  validateArtifactPathClaimsV1 claims
  -- Sidecar collision messages preserved for product diagnostics.
  for c in claims do
    if c.path == evidenceSidecarNameV1 then
      pathError s!"sidecar path collides with artifact '{evidenceSidecarNameV1}'"
    if c.path == manifestSidecarNameV1 then
      pathError s!"sidecar path collides with artifact '{manifestSidecarNameV1}'"
  let mut auxSeen : Array String := #[]
  for path in auxiliaryLeaves do
    unless safeRelativeArtifactPathV1 path do
      pathError s!"unsafe artifact path '{path}'"
    if auxSeen.contains path then
      pathError s!"duplicate artifact path '{path}'"
    -- Claim vs aux path collision (generic).
    if claims.any (·.path == path) then
      if isFixedSidecarPathV1 path then
        pathError s!"sidecar path collides with artifact '{path}'"
      else
        pathError s!"duplicate artifact path '{path}'"
    auxSeen := auxSeen.push path
  let claimPaths := claims.map (·.path)
  let leaves := claimPaths ++ auxiliaryLeaves
  if leaves.size > maxEngineeringDiskClosureFilesV1 then
    limitError s!"too many closure files ({leaves.size} > {maxEngineeringDiskClosureFilesV1})"
  -- Full-set uniqueness (defensive) + prefix across all leaves.
  let mut fullSeen : Array String := #[]
  for path in leaves do
    unless safeRelativeArtifactPathV1 path do
      pathError s!"unsafe artifact path '{path}'"
    if fullSeen.contains path then
      pathError s!"duplicate artifact path '{path}'"
    fullSeen := fullSeen.push path
  for a in leaves do
    for b in leaves do
      if a != b && b.startsWith (a ++ "/") then
        pathError s!"file/directory prefix conflict '{a}'"
  pure leaves

/-- Pure descriptor validation: legal digest, safe path, closed role, size. -/
def validateArtifactContentDescriptorV1 (d : ArtifactContentDescriptorV1) : IO Unit := do
  unless safeRelativeArtifactPathV1 d.path do
    pathError s!"unsafe artifact path '{d.path}'"
  match validateDigest d.contentSha256 with
  | .ok () => pure ()
  | .error _ =>
      pathError s!"invalid content digest for '{d.path}'"
  match d.contentSha256.algorithm with
  | .sha256 => pure ()
  if d.size > maxEngineeringDiskClosureFileBytesV1 then
    limitError s!"file exceeds size limit '{d.path}'"

/-- Pure inventory validation: sorted, unique, digests legal, no prefix/sidecar. -/
def validateArtifactContentInventoryV1 (inv : ArtifactContentInventoryV1) : IO Unit := do
  let ds := ArtifactContentInventoryV1.descriptorsOf inv
  if ds.size > maxEngineeringDiskClosureFilesV1 then
    limitError s!"too many artifact descriptors ({ds.size} > {maxEngineeringDiskClosureFilesV1})"
  let mut claims : Array ArtifactPathClaimV1 := #[]
  let mut totalBytes : Nat := 0
  for d in ds do
    validateArtifactContentDescriptorV1 d
    totalBytes := totalBytes + d.size
    if totalBytes > maxEngineeringDiskClosureTotalBytesV1 then
      limitError s!"artifact inventory total size exceeds limit at '{d.path}'"
    claims := claims.push { role := d.role, path := d.path }
  validateArtifactPathClaimsV1 claims
  for c in claims do
    if isFixedSidecarPathV1 c.path then
      pathError s!"sidecar path collides with artifact '{c.path}'"
  -- Exact canonical order.
  let sorted := sortArtifactContentDescriptorsV1 ds
  unless ds.size == sorted.size do
    pathError "artifact inventory order is noncanonical"
  for pair in ds.zip sorted do
    unless ArtifactContentDescriptorV1.beq pair.1 pair.2 do
      pathError "artifact inventory order is noncanonical"

/-! ## Physical walk helpers (sole walker) -/

private def pathComponents (path : String) : List String :=
  path.splitOn "/" |>.filter (fun c => !c.isEmpty)

private def isDirectChildOf (parent : String) (path : String) : Bool :=
  if parent.isEmpty then
    !(path.contains '/')
  else
    let pre := parent ++ "/"
    path.startsWith pre && !((path.drop pre.length).contains '/')

private def expectedDirectChildCount
    (rel : String) (expectedLeaves expectedDirs : Array String) : Nat := Id.run do
  let mut n : Nat := 0
  for leaf in expectedLeaves do
    if isDirectChildOf rel leaf then
      n := n + 1
  for d in expectedDirs do
    if isDirectChildOf rel d then
      n := n + 1
  pure n

private def parentDirPrefixes (path : String) : Array String := Id.run do
  let components := pathComponents path
  let mut out : Array String := #[]
  let mut acc : String := ""
  let mut rest := components
  while rest.length > 1 do
    match rest with
    | c :: cs =>
        acc := if acc.isEmpty then c else acc ++ "/" ++ c
        out := out.push acc
        rest := cs
    | [] => break
  pure out

private def sortDirEntries (entries : Array IO.FS.DirEntry) : Array IO.FS.DirEntry :=
  entries.qsort fun a b => a.fileName < b.fileName

private def expectedDirsOf (leaves : Array String) : Array String := Id.run do
  let mut dirs : Array String := #[]
  for leaf in leaves do
    for d in parentDirPrefixes leaf do
      unless dirs.contains d do
        dirs := dirs.push d
  pure dirs

private def joinRelative (parent child : String) : String :=
  if parent.isEmpty then child else parent ++ "/" ++ child

/-- Key metadata slice used for before/after stable observation (no atime). -/
structure ArtifactFileMetaObservationV1 where
  type : IO.FS.FileType
  numLinks : UInt64
  byteSize : UInt64
  deriving BEq, Repr

def observeFileMetaV1 (md : IO.FS.Metadata) : ArtifactFileMetaObservationV1 :=
  { type := md.type, numLinks := md.numLinks, byteSize := md.byteSize }

/-- Bounded no-follow physical walk: exact leaf/dir membership, type, size caps. -/
private def walkPhysicalClosureV1
    (stagingDir : FilePath) (expectedLeaves expectedDirs : Array String) : IO Unit := do
  let rootMeta ← try stagingDir.symlinkMetadata
    catch _ => pathError "staging root is missing"
  unless rootMeta.type == .dir do
    pathError "staging root is not a real directory"
  let mut worklist : Array String := #[""]
  let mut head : Nat := 0
  let mut observedFiles : Array String := #[]
  let mut observedDirs : Array String := #[]
  let mut totalBytes : Nat := 0
  let maxVisits := expectedDirs.size + expectedLeaves.size + 8
  let mut visits : Nat := 0
  while head < worklist.size do
    visits := visits + 1
    if visits > maxVisits then
      pathError "staging walk exceeded bounded worklist"
    let rel := worklist[head]!
    head := head + 1
    let dirPath := if rel.isEmpty then stagingDir else stagingDir / rel
    let dirMeta ← try dirPath.symlinkMetadata
      catch _ =>
        pathError (if rel.isEmpty then "staging root is missing"
          else s!"missing directory '{rel}'")
    unless dirMeta.type == .dir do
      pathError (if rel.isEmpty then "staging root is not a real directory"
        else s!"path is not a directory '{rel}'")
    let rawEntries ← dirPath.readDir
    let maxEntries :=
      expectedDirectChildCount rel expectedLeaves expectedDirs +
        maxEngineeringDiskClosureDirEntrySlackV1
    if rawEntries.size > maxEntries then
      let dirLabel := if rel.isEmpty then "." else rel
      limitError
        s!"too many directory entries under '{dirLabel}' ({rawEntries.size} > {maxEntries})"
    let entries := sortDirEntries rawEntries
    for entry in entries do
      let name := entry.fileName
      if name == "." || name == ".." || name.contains "/" || name.isEmpty then
        pathError s!"invalid directory entry name under '{rel}'"
      let childRel := joinRelative rel name
      let childPath := entry.path
      let childMeta ← try childPath.symlinkMetadata
        catch _ => pathError s!"missing path '{childRel}'"
      match childMeta.type with
      | .symlink =>
          pathError s!"path is a symbolic link '{childRel}'"
      | .other =>
          pathError s!"non-regular filesystem entry '{childRel}'"
      | .dir =>
          unless expectedDirs.contains childRel do
            pathError s!"unexpected directory '{childRel}'"
          if observedDirs.contains childRel then
            pathError s!"duplicate directory observation '{childRel}'"
          observedDirs := observedDirs.push childRel
          worklist := worklist.push childRel
      | .file =>
          unless expectedLeaves.contains childRel do
            pathError s!"unexpected file '{childRel}'"
          if observedFiles.contains childRel then
            pathError s!"duplicate file observation '{childRel}'"
          let size := childMeta.byteSize.toNat
          if size > maxEngineeringDiskClosureFileBytesV1 then
            limitError s!"file exceeds size limit '{childRel}'"
          let nextTotal := totalBytes + size
          if nextTotal > maxEngineeringDiskClosureTotalBytesV1 then
            limitError s!"total closure size exceeds limit at '{childRel}'"
          totalBytes := nextTotal
          observedFiles := observedFiles.push childRel
  for leaf in expectedLeaves do
    unless observedFiles.contains leaf do
      pathError s!"missing regular file '{leaf}'"
  for d in expectedDirs do
    unless observedDirs.contains d do
      pathError s!"missing directory '{d}'"
  pure ()

/-- Stable content observation: before/after symlinkMetadata + readBinFile + SHA-256.

    Requires regular file, numLinks=1, size==bytes.size, key meta unchanged.
    Engineering observation only — no retained fd / TOCTOU claim. -/
private def readArtifactContentStableV1 (rel : String) (abs : FilePath) :
    IO (Nat × Digest) := do
  let before ← try abs.symlinkMetadata
    catch _ => pathError s!"missing regular file '{rel}'"
  unless before.type == .file do
    pathError s!"missing regular file '{rel}'"
  unless before.numLinks == 1 do
    pathError s!"path is not a single-link regular file '{rel}'"
  let sizeBefore := before.byteSize.toNat
  if sizeBefore > maxEngineeringDiskClosureFileBytesV1 then
    limitError s!"file exceeds size limit '{rel}'"
  let beforeObs := observeFileMetaV1 before
  let bytes ← IO.FS.readBinFile abs
  let after ← try abs.symlinkMetadata
    catch _ => pathError s!"missing regular file '{rel}'"
  let afterObs := observeFileMetaV1 after
  unless afterObs == beforeObs do
    pathError s!"file metadata changed during read '{rel}'"
  unless after.type == .file do
    pathError s!"missing regular file '{rel}'"
  unless after.numLinks == 1 do
    pathError s!"path is not a single-link regular file '{rel}'"
  unless after.byteSize.toNat == bytes.size do
    pathError s!"file size mismatch during read '{rel}'"
  pure (bytes.size, sha256Bytes bytes)

/-- Aux leaf: same stable single-link observation as artifacts; digest discarded. -/
private def checkAuxLeafStableV1 (rel : String) (abs : FilePath) : IO Unit := do
  let _ ← readArtifactContentStableV1 rel abs
  pure ()

/-- Sole IO scanner/walker: exact directory closure + artifact content inventory.

    `claims` may be trusted or untrusted — pure validation runs first.
    `auxiliaryLeaves` (e.g. evidence.json, manifest.json) join exact closure and
    byte caps but are excluded from the returned inventory.

    Engineering static observation only; not race-free / contained / formal. -/
def scanArtifactContentClosureV1
    (stagingDir : FilePath)
    (claims : Array ArtifactPathClaimV1)
    (auxiliaryLeaves : Array String) :
    IO ArtifactContentInventoryV1 := do
  let leaves ← validateArtifactClaimsAgainstAuxV1 claims auxiliaryLeaves
  let dirs := expectedDirsOf leaves
  walkPhysicalClosureV1 stagingDir leaves dirs
  -- Content phase: claims in canonical order → descriptors.
  let ordered := sortArtifactPathClaimsV1 claims
  let mut descriptors : Array ArtifactContentDescriptorV1 := #[]
  for c in ordered do
    let abs := stagingDir / c.path
    let (size, digest) ← readArtifactContentStableV1 c.path abs
    descriptors := descriptors.push {
      role := c.role
      path := c.path
      size := size
      contentSha256 := digest
    }
  for aux in auxiliaryLeaves do
    checkAuxLeafStableV1 aux (stagingDir / aux)
  let inv := ArtifactContentInventoryV1.mk descriptors
  validateArtifactContentInventoryV1 inv
  pure inv

end ProofForgeV2
