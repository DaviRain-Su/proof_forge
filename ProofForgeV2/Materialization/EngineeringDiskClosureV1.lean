/-
  Engineering exact disk-closure validator (D3/S7c).

  Sole production entry: `validateEngineeringDiskClosureV1` consumes only the
  private-ctor `FinalizedArtifactsV1` authority and a staging directory. Expected
  physical leaves are derived exclusively from ordered base artifact paths +
  finalized extra paths + fixed transitional sidecars `evidence.json` and
  `manifest.json` — no caller-supplied expected list.

  Pre-walk logical gates: `safeRelativeArtifactPathV1`, exact byte-string
  uniqueness, sidecar collision, file/directory prefix conflicts, and bounded
  limits. Physical walk: explicit bounded worklist, `symlinkMetadata` no-follow,
  deterministic raw-name sort; rejects missing/extra/symlink/nonregular/type
  mismatch with stable relative-path errors only.

  Does not inspect or mutate artifact contents. Not formal OutputSetV1 /
  proof-forge.output.v1 / BuildIdentity / hermetic publisher / crash durability.
-/
import ProofForgeV2.Materialization.EngineeringFinalizationV1
import ProofForgeV2.Materialization.MaterializedArtifactsV1

namespace ProofForgeV2

open System

/-- Max regular files in a published engineering closure (incl. sidecars). -/
def maxEngineeringDiskClosureFilesV1 : Nat := 1024

/-- Max bytes per regular file (metadata size only; contents unread). -/
def maxEngineeringDiskClosureFileBytesV1 : Nat := 64 * 1024 * 1024

/-- Max total bytes across all regular files in the closure. -/
def maxEngineeringDiskClosureTotalBytesV1 : Nat := 256 * 1024 * 1024

/-- Fixed transitional evidence sidecar name (not listed in manifest.files). -/
def evidenceSidecarNameV1 : String := "evidence.json"

/-- Fixed transitional manifest sidecar name (last file write in publisher). -/
def manifestSidecarNameV1 : String := "manifest.json"

/-- Slack entries beyond exact expected direct children before PF-OUTPUT-LIMIT. -/
def maxEngineeringDiskClosureDirEntrySlackV1 : Nat := 8

private def pathError (message : String) : IO α :=
  throw <| IO.userError s!"PF-OUTPUT-PATH: {message}"

private def limitError (message : String) : IO α :=
  throw <| IO.userError s!"PF-OUTPUT-LIMIT: {message}"

/-- Split a validated relative path into non-empty components. -/
private def pathComponents (path : String) : List String :=
  path.splitOn "/" |>.filter (fun c => !c.isEmpty)

/-- Proper path-prefix relation on `/`-joined relative paths (byte-string). -/
private def isProperPathPrefix (pre full : String) : Bool :=
  full.startsWith (pre ++ "/")

/-- True when `path` is exactly one path component under `parent` (root=`""`). -/
private def isDirectChildOf (parent : String) (path : String) : Bool :=
  if parent.isEmpty then
    !(path.contains '/')
  else
    let pre := parent ++ "/"
    path.startsWith pre && !((path.drop pre.length).contains '/')

/-- Count expected direct children (leaves + intermediate dirs) under `rel`. -/
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

/-- Parent directory prefixes of a relative leaf (empty root excluded). -/
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

/-- Stable UTF-8 raw-name order for directory entries (byte-string). -/
private def sortDirEntries (entries : Array IO.FS.DirEntry) : Array IO.FS.DirEntry :=
  entries.qsort fun a b => a.fileName < b.fileName

/-- Ordered artifact leaves from finalized carrier (base then extras; no sidecars). -/
private def artifactLeavesOf (finalized : FinalizedArtifactsV1) : Array String :=
  let base :=
    (MaterializedArtifactsV1.filesOf (FinalizedArtifactsV1.artifactsOf finalized)).map (·.path)
  let extras := FinalizedArtifactsV1.extraFilesOf finalized
  base ++ extras

/-- Derive intermediate directory set from expected leaves. -/
private def expectedDirsOf (leaves : Array String) : Array String := Id.run do
  let mut dirs : Array String := #[]
  for leaf in leaves do
    for d in parentDirPrefixes leaf do
      unless dirs.contains d do
        dirs := dirs.push d
  pure dirs

/-- Pre-walk logical gates: artifacts first, then sidecars, then full-set rules. -/
private def validateExpectedLogical (artifactLeaves : Array String) : IO (Array String) := do
  -- Safety + uniqueness on base/extras only (mint dual-defense; re-check here).
  let mut seen : Array String := #[]
  for path in artifactLeaves do
    unless safeRelativeArtifactPathV1 path do
      pathError s!"unsafe artifact path '{path}'"
    if seen.contains path then
      pathError s!"duplicate artifact path '{path}'"
    seen := seen.push path
  -- Sidecar names must not collide with base/extra leaves before append.
  if artifactLeaves.contains evidenceSidecarNameV1 then
    pathError s!"sidecar path collides with artifact '{evidenceSidecarNameV1}'"
  if artifactLeaves.contains manifestSidecarNameV1 then
    pathError s!"sidecar path collides with artifact '{manifestSidecarNameV1}'"
  let leaves := artifactLeaves ++ #[evidenceSidecarNameV1, manifestSidecarNameV1]
  if leaves.size > maxEngineeringDiskClosureFilesV1 then
    limitError s!"too many closure files ({leaves.size} > {maxEngineeringDiskClosureFilesV1})"
  -- Full-set uniqueness (sidecars are fixed distinct names; defensive).
  let mut fullSeen : Array String := #[]
  for path in leaves do
    unless safeRelativeArtifactPathV1 path do
      pathError s!"unsafe artifact path '{path}'"
    if fullSeen.contains path then
      pathError s!"duplicate artifact path '{path}'"
    fullSeen := fullSeen.push path
  -- File/directory prefix conflicts: a leaf must not be a proper prefix of another.
  for i in [:leaves.size] do
    let a := leaves[i]!
    for j in [:leaves.size] do
      if i != j && isProperPathPrefix a leaves[j]! then
        pathError s!"file/directory prefix conflict '{a}'"
  pure leaves

private def joinRelative (parent child : String) : String :=
  if parent.isEmpty then child else parent ++ "/" ++ child

/-- Bounded no-follow physical walk of staging against derived expected sets. -/
private def walkPhysicalClosure
    (stagingDir : FilePath) (expectedLeaves expectedDirs : Array String) : IO Unit := do
  -- Root must exist as a real directory (no symlink root).
  let rootMeta ← try stagingDir.symlinkMetadata
    catch _ => pathError "staging root is missing"
  unless rootMeta.type == .dir do
    pathError "staging root is not a real directory"
  let mut worklist : Array String := #[""]
  let mut head : Nat := 0
  let mut observedFiles : Array String := #[]
  let mut observedDirs : Array String := #[]
  let mut totalBytes : Nat := 0
  -- Bound visits: root + every expected dir + slack for reject path.
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
    -- Per-directory entry cap before sort: exact expected direct children + slack.
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
  -- Exact membership: every expected leaf and dir must have been observed.
  for leaf in expectedLeaves do
    unless observedFiles.contains leaf do
      pathError s!"missing regular file '{leaf}'"
  for d in expectedDirs do
    unless observedDirs.contains d do
      pathError s!"missing directory '{d}'"
  pure ()

/-- Sole production engineering exact disk-closure validator (D3/S7c).

    Inputs: private `FinalizedArtifactsV1` + staging `FilePath`.
    Expected leaves = ordered base paths + ordered extras + `evidence.json` +
    `manifest.json`. No caller expected-list parameter. Does not read file
    contents; size limits use metadata only. -/
def validateEngineeringDiskClosureV1
    (finalized : FinalizedArtifactsV1) (stagingDir : FilePath) : IO Unit := do
  let leaves ← validateExpectedLogical (artifactLeavesOf finalized)
  let dirs := expectedDirsOf leaves
  walkPhysicalClosure stagingDir leaves dirs

end ProofForgeV2
