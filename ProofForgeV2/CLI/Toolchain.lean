import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
import ProofForgeV2.Core.Source

namespace ProofForgeV2.CLI.Toolchain

open Lean ProofForgeV2 System

structure LockedRuntimeFile where
  path : String
  sha256 : String
  deriving FromJson, Repr

structure LockedTool where
  id : String
  version : String
  sourceUrl : String
  platform : String
  assetId : String
  executable : String
  defaultPath : String
  executableSha256 : String
  runtimeLibrarySubdir : Option String
  runtimeFiles : Array LockedRuntimeFile
  versionArgs : Array String
  expectedVersion : String
  licenseSpdx : String
  requiredByProfiles : Array String
  deriving FromJson, Repr

structure LockedBundleFile where
  path : String
  size : Nat
  sha256 : String
  mode : String
  deriving FromJson, Repr

structure LockFile where
  schema : String
  bundleFiles : Array LockedBundleFile
  tools : Array LockedTool
  deriving FromJson, Repr

structure LockedSystemTool where
  id : String
  path : String
  sha256 : String
  deriving FromJson, Repr

structure LockedHostProfile where
  id : String
  systemTools : Array LockedSystemTool
  deriving FromJson, Repr

structure HostLockFile where
  schema : String
  profiles : Array LockedHostProfile
  deriving FromJson, Repr

private structure VerifiedSystemTool where
  id : String
  path : FilePath
  sha256 : String
  deriving Repr

structure VerifiedTool where
  id : String
  path : FilePath
  launcher : FilePath
  version : String
  executableSha256 : String
  processEnvironment : Array (String × String)
  deriving Repr

private def embeddedLockDarwin : String := include_str "../../toolchains.lock.json"
private def embeddedLockLinux : String := include_str "../../toolchains-linux-x86_64.lock.json"
private def embeddedHostLock : String := include_str "../../host-profiles.lock.json"

private def isDarwinHost : Bool := System.Platform.isOSX

private def expectedLockSchema : String :=
  if isDarwinHost then "proof-forge.toolchains.v2" else "proof-forge.toolchains.v3"

private def loadLock : Except String LockFile := do
  let embedded := if isDarwinHost then embeddedLockDarwin else embeddedLockLinux
  let lock : LockFile ← Json.parse embedded >>= fromJson?
  unless lock.schema == expectedLockSchema do
    throw s!"unsupported toolchain lock schema '{lock.schema}'"
  return lock

private def loadHostLock : Except String HostLockFile := do
  let lock : HostLockFile ← Json.parse embeddedHostLock >>= fromJson?
  unless lock.schema == "proof-forge.host-profiles.v2" do
    throw s!"unsupported host lock schema '{lock.schema}'"
  return lock

private def throwCompile (error : CompileError) : IO α :=
  throw <| IO.userError error.render

private def mismatch (message : String) : IO α :=
  throw <| IO.userError s!"PF-TOOLCHAIN-MISMATCH: {message}"

private def safeRelativeComponents (label path : String) : IO (List String) := do
  let components := path.splitOn "/"
  if path.isEmpty || path.startsWith "/" || path.contains "\\" ||
      components.any fun component => component.isEmpty || component == "." || component == ".." then
    mismatch s!"unsafe {label} path '{path}'"
  return components

private def parentPaths (components : List String) : List String :=
  let rec go (parent : String) : List String → List String
    | [] | [_] => []
    | component :: remaining =>
        let next := if parent.isEmpty then component else parent ++ "/" ++ component
        next :: go next remaining
  go "" components

private def validateLockClosure (lock : LockFile) : IO Unit := do
  let mut filePaths : Array String := #[]
  for file in lock.bundleFiles do
    let _ ← safeRelativeComponents "bundle file" file.path
    if filePaths.contains file.path then
      mismatch s!"duplicate bundle file '{file.path}'"
    if file.size == 0 then
      mismatch s!"bundle file '{file.path}' must have a non-zero size"
    if file.sha256.length != 64 then
      mismatch s!"bundle file '{file.path}' has an invalid SHA-256"
    filePaths := filePaths.push file.path
  for tool in lock.tools do
    let _ ← safeRelativeComponents s!"{tool.id} executable" tool.executable
    let executableFile ← match lock.bundleFiles.find? (·.path == tool.executable) with
      | some file => pure file
      | none => mismatch s!"{tool.id} executable is absent from bundleFiles"
    unless executableFile.sha256 == tool.executableSha256 do
      mismatch s!"{tool.id} executable hash disagrees with bundleFiles"
    for runtimeFile in tool.runtimeFiles do
      let _ ← safeRelativeComponents s!"{tool.id} runtime file" runtimeFile.path
      let bundled ← match lock.bundleFiles.find? (·.path == runtimeFile.path) with
        | some file => pure file
        | none => mismatch s!"{tool.id} runtime file '{runtimeFile.path}' is absent from bundleFiles"
      unless bundled.sha256 == runtimeFile.sha256 do
        mismatch s!"{tool.id} runtime file hash disagrees with bundleFiles"
    if let some subdir := tool.runtimeLibrarySubdir then
      let _ ← safeRelativeComponents s!"{tool.id} runtime library" subdir
      unless tool.runtimeFiles.any fun file =>
          file.path.startsWith (subdir ++ "/") do
        mismatch s!"{tool.id} runtime library directory has no locked runtime file"

private def defaultPath (tool : LockedTool) : IO FilePath := do
  if tool.defaultPath.startsWith "~/" then
    let home ← IO.getEnv "HOME"
    match home with
    | some value => pure <| FilePath.mk value / (tool.defaultPath.drop 2).copy
    | none => throw <| IO.userError "PF-TOOLCHAIN-MISSING: HOME is required for the default tool cache"
  else
    pure <| FilePath.mk tool.defaultPath

private def candidatePath (tool : LockedTool) : IO FilePath := do
  match ← IO.getEnv "PROOF_FORGE_TOOL_ROOT" with
  | none => defaultPath tool
  | some root =>
      let rootPath := FilePath.mk root
      unless rootPath.isAbsolute do
        throw <| IO.userError "PF-TOOLCHAIN-MISMATCH: PROOF_FORGE_TOOL_ROOT must be absolute"
      pure <| rootPath / tool.executable

def isolatedEnvironment : Array (String × String) := #[
  ("LC_ALL", "C"),
  ("TZ", "UTC")
]

private def withRuntimeLibrary (environment : Array (String × String))
    (libraryPath : String) : Array (String × String) :=
  let envVar := if isDarwinHost then "DYLD_LIBRARY_PATH" else "LD_LIBRARY_PATH"
  environment.push (envVar, libraryPath)

private def lockedProcessEnvironment (tool : LockedTool) (executable : FilePath) : IO (Array (String × String)) := do
  let root ← IO.FS.realPath <| executable.parent.getD "."
  for runtimeFile in tool.runtimeFiles do
    let relative := FilePath.mk runtimeFile.path
    if relative.isAbsolute || runtimeFile.path.isEmpty || runtimeFile.path.contains ".." ||
        runtimeFile.path.contains "\\" then
      throw <| IO.userError s!"PF-TOOLCHAIN-MISMATCH: unsafe runtime file path for {tool.id}"
    let candidate := root / relative
    let metadata ← candidate.symlinkMetadata
    if metadata.type == .symlink then
      throw <| IO.userError s!"PF-TOOLCHAIN-MISMATCH: runtime file cannot be a symlink for {tool.id}"
    let realPath ← IO.FS.realPath candidate
    unless realPath.toString.startsWith (root.toString ++ "/") do
      throw <| IO.userError s!"PF-TOOLCHAIN-MISMATCH: runtime file escaped tool root for {tool.id}"
    let actualHash := Crypto.sha256Hex (← IO.FS.readBinFile realPath)
    unless actualHash == runtimeFile.sha256 do
      throwCompile <| .toolchainMismatch s!"{tool.id}:{runtimeFile.path}" runtimeFile.sha256 actualHash
  match tool.runtimeLibrarySubdir with
  | none => pure isolatedEnvironment
  | some subdir =>
      let relative := FilePath.mk subdir
      if relative.isAbsolute || subdir.isEmpty || subdir.contains ".." || subdir.contains "\\" then
        throw <| IO.userError s!"PF-TOOLCHAIN-MISMATCH: unsafe runtime library path for {tool.id}"
      let libraryCandidate := root / relative
      unless ← libraryCandidate.pathExists do
        throw <| IO.userError s!"PF-TOOLCHAIN-MISSING: runtime library directory {libraryCandidate}"
      let library ← IO.FS.realPath libraryCandidate
      unless library.toString.startsWith (root.toString ++ "/") do
        throw <| IO.userError s!"PF-TOOLCHAIN-MISMATCH: runtime library path escaped tool root for {tool.id}"
      pure <| withRuntimeLibrary isolatedEnvironment library.toString

private def profileMatchesHost (profile : Json) : Bool :=
  match profile.getObjVal? "platform" with
  | .error _ => false
  | .ok platform =>
      let key := if isDarwinHost then "productVersion" else "osReleaseId"
      match platform.getObjVal? key with
      | .ok _ => true
      | .error _ => false

private def singleHostProfile : IO LockedHostProfile := do
  let root ← match Json.parse embeddedHostLock with
    | .ok value => pure value
    | .error message =>
        throw <| IO.userError s!"PF-TOOLCHAIN-MISMATCH: invalid embedded host lock: {message}"
  let schema ← match root.getObjVal? "schema" with
    | .ok (.str value) => pure value
    | _ => throw <| IO.userError "PF-TOOLCHAIN-MISMATCH: invalid embedded host lock schema"
  unless schema == "proof-forge.host-profiles.v2" do
    throw <| IO.userError s!"PF-TOOLCHAIN-MISMATCH: unsupported host lock schema '{schema}'"
  let profiles ← match root.getObjVal? "profiles" with
    | .ok (.arr values) => pure values
    | _ => throw <| IO.userError "PF-TOOLCHAIN-MISMATCH: invalid embedded host lock profiles"
  let matching := profiles.filter profileMatchesHost
  unless matching.size == 1 do
    throw <| IO.userError "PF-TOOLCHAIN-MISMATCH: exactly one host profile for this platform is required"
  let profile ← match (fromJson? matching[0]! : Except String LockedHostProfile) with
    | .ok parsed => pure parsed
    | .error message =>
        throw <| IO.userError s!"PF-TOOLCHAIN-MISMATCH: invalid host profile: {message}"
  return profile

private def verifyRegularFile (label : String) (path : FilePath) (expectedHash : String)
    (requireSingleLink : Bool) : IO FilePath := do
  unless path.isAbsolute && (← path.pathExists) do
    throw <| IO.userError s!"PF-TOOLCHAIN-MISSING: {label} {path}"
  let before ← path.symlinkMetadata
  unless before.type == .file do
    mismatch s!"{label} must be a regular file"
  if requireSingleLink && before.numLinks != 1 then
    mismatch s!"{label} must have exactly one hard link"
  let realPath ← IO.FS.realPath path
  let bytes ← IO.FS.readBinFile realPath
  let after ← path.symlinkMetadata
  unless after.type == .file do
    mismatch s!"{label} changed type while being verified"
  if requireSingleLink && after.numLinks != 1 then
    mismatch s!"{label} gained an additional hard link while being verified"
  unless before.byteSize == after.byteSize && after.byteSize.toNat == bytes.size do
    mismatch s!"{label} changed size while being verified"
  let actualHash := Crypto.sha256Hex bytes
  unless actualHash == expectedHash do
    throwCompile <| .toolchainMismatch label expectedHash actualHash
  return realPath

private def resolveSystemToolBasic (profile : LockedHostProfile) (id : String)
    (requireSingleLink : Bool) : IO VerifiedSystemTool := do
  let locked ← match profile.systemTools.find? (·.id == id) with
    | some tool => pure tool
    | none => throw <| IO.userError s!"PF-TOOLCHAIN-MISSING: host system tool '{id}'"
  let path ← verifyRegularFile s!"host:{id}" (FilePath.mk locked.path) locked.sha256 requireSingleLink
  return { id, path, sha256 := locked.sha256 }

private def isOctalDigit (char : Char) : Bool :=
  '0' ≤ char && char ≤ '7'

private def hasWriteBit (char : Char) : Bool :=
  char == '2' || char == '3' || char == '6' || char == '7'

private def permissionMode (statTool : VerifiedSystemTool)
    (label : String) (path : FilePath) : IO String := do
  let args := if isDarwinHost then
    #["-f", "%Lp", "--", path.toString]
  else
    #["-c", "%a", "--", path.toString]
  let output ← IO.Process.output {
    cmd := statTool.path.toString
    args := args
    inheritEnv := false
  }
  unless output.exitCode == 0 do
    mismatch s!"cannot inspect permissions for {label}: stat exited {output.exitCode}"
  let mode := output.stdout.trimAscii.copy
  let digits := mode.toList
  unless digits.length >= 3 && digits.all isOctalDigit do
    mismatch s!"invalid permission mode '{mode}' for {label}"
  return mode

private def verifySafePermissionMode (label mode : String) : IO Unit := do
  let digits := mode.toList
  match digits.reverse with
  | other :: group :: _ =>
      if hasWriteBit group || hasWriteBit other then
        mismatch s!"{label} is group/world writable (mode {mode})"
  | _ => mismatch s!"invalid permission mode '{mode}' for {label}"

private def verifyNotGroupOrWorldWritable (statTool : VerifiedSystemTool)
    (label : String) (path : FilePath) : IO Unit := do
  verifySafePermissionMode label (← permissionMode statTool label path)

private def normalizeLockedMode (label mode : String) : IO Nat := do
  unless !mode.isEmpty && mode.toList.all isOctalDigit do
    mismatch s!"invalid locked permission mode '{mode}' for {label}"
  match mode.toNat? with
  | some value => pure value
  | none => mismatch s!"invalid locked permission mode '{mode}' for {label}"

private partial def absolutePathChain (path : FilePath) : List FilePath :=
  match path.parent with
  | none => [path]
  | some parent => absolutePathChain parent ++ [path]

private def verifyProtectedPath (statTool : VerifiedSystemTool) (label : String)
    (path : FilePath) (lastType : IO.FS.FileType) : IO Unit := do
  let chain := absolutePathChain path
  for component in chain do
    let metadata ← component.symlinkMetadata
    if metadata.type == .symlink then
      mismatch s!"{label} path contains symlink '{component}'"
    let expectedType := if component == path then lastType else .dir
    unless metadata.type == expectedType do
      mismatch s!"{label} path has unexpected node type at '{component}'"
    verifyNotGroupOrWorldWritable statTool label component

private def resolveStat : IO VerifiedSystemTool := do
  let profile ← singleHostProfile
  -- Darwin's signed `/usr/bin/stat` has two system-owned hard links. Its exact
  -- content is locked, then it is used only to inspect permission bits that
  -- Lean's portable Metadata API does not expose.
  let statTool ← resolveSystemToolBasic profile "stat" false
  verifyProtectedPath statTool "host:stat" statTool.path .file
  return statTool

private def resolveLauncher : IO (VerifiedSystemTool × VerifiedSystemTool) := do
  let profile ← singleHostProfile
  let statTool ← resolveStat
  let launcher ← resolveSystemToolBasic profile "env" true
  verifyProtectedPath statTool "host:env" launcher.path .file
  return (launcher, statTool)

private def expectedDirectories (files : Array LockedBundleFile) : IO (Array String) := do
  let mut directories : Array String := #[]
  for file in files do
    let components ← safeRelativeComponents "bundle file" file.path
    for path in parentPaths components do
      unless directories.contains path do
        directories := directories.push path
  return directories

private def verifyBundleFile (statTool : VerifiedSystemTool) (root : FilePath)
    (locked : LockedBundleFile) (path : FilePath) : IO Unit := do
  let before ← path.symlinkMetadata
  unless before.type == .file do
    mismatch s!"bundle node '{locked.path}' must be a regular file"
  unless before.numLinks == 1 do
    mismatch s!"bundle file '{locked.path}' must have exactly one hard link"
  unless before.byteSize.toNat == locked.size do
    mismatch s!"bundle file '{locked.path}' has size {before.byteSize}, expected {locked.size}"
  let realPath ← IO.FS.realPath path
  unless realPath == path && realPath.toString.startsWith (root.toString ++ "/") do
    mismatch s!"bundle file '{locked.path}' escaped the verified tool root"
  let label := s!"bundle:{locked.path}"
  let actualMode ← permissionMode statTool label path
  verifySafePermissionMode label actualMode
  let actualModeValue ← normalizeLockedMode label actualMode
  let expectedModeValue ← normalizeLockedMode label locked.mode
  unless actualModeValue == expectedModeValue do
    mismatch s!"{label} has mode {actualMode}, expected {locked.mode}"
  let bytes ← IO.FS.readBinFile path
  let after ← path.symlinkMetadata
  unless after.type == .file && after.numLinks == 1 && after.byteSize == before.byteSize &&
      after.byteSize.toNat == bytes.size do
    mismatch s!"bundle file '{locked.path}' changed while being verified"
  let actualHash := Crypto.sha256Hex bytes
  unless actualHash == locked.sha256 do
    throwCompile <| .toolchainMismatch s!"bundle:{locked.path}" locked.sha256 actualHash

private partial def verifyBundleDirectory (statTool : VerifiedSystemTool) (root current : FilePath)
    (relative : String) (files : Array LockedBundleFile) (directories : Array String) :
    IO (Array String) := do
  let metadata ← current.symlinkMetadata
  unless metadata.type == .dir do
    mismatch s!"bundle directory '{relative}' is not a directory"
  verifyNotGroupOrWorldWritable statTool
    (if relative.isEmpty then "bundle root" else s!"bundle:{relative}") current
  let mut observed : Array String := #[]
  for entry in (← current.readDir) do
    if entry.fileName == "." || entry.fileName == ".." || entry.fileName.contains "/" then
      mismatch s!"invalid directory entry '{entry.fileName}' in tool bundle"
    let childRelative := if relative.isEmpty then entry.fileName else relative ++ "/" ++ entry.fileName
    let child := entry.path
    let childMetadata ← child.symlinkMetadata
    if childMetadata.type == .symlink then
      mismatch s!"tool bundle cannot contain symlink '{childRelative}'"
    if directories.contains childRelative then
      unless childMetadata.type == .dir do
        mismatch s!"bundle node '{childRelative}' must be a directory"
      observed := observed ++ (← verifyBundleDirectory statTool root child childRelative files directories)
    else
      match files.find? (·.path == childRelative) with
      | some locked =>
          verifyBundleFile statTool root locked child
          observed := observed.push childRelative
      | none => mismatch s!"unexpected node '{childRelative}' in tool bundle"
  return observed

private def verifyBundleRoot (statTool : VerifiedSystemTool) (root : FilePath)
    (files : Array LockedBundleFile) : IO Unit := do
  unless root.isAbsolute do mismatch "tool bundle root must be absolute"
  let rootMetadata ← root.symlinkMetadata
  unless rootMetadata.type == .dir do
    mismatch "tool bundle root must be a real directory"
  let realRoot ← IO.FS.realPath root
  unless realRoot == root do
    mismatch "tool bundle root cannot contain a symlink or unresolved component"
  let directories ← expectedDirectories files
  let observed ← verifyBundleDirectory statTool root root "" files directories
  unless observed.size == files.size && files.all fun file => observed.contains file.path do
    mismatch "tool bundle is missing one or more locked files"

private def validateProcessEnvironment (environment : Array (String × String)) : IO Unit := do
  let mut keys : Array String := #[]
  for (key, _value) in environment do
    if key.isEmpty || key.contains "=" then
      mismatch s!"invalid process environment key '{key}'"
    if keys.contains key then
      mismatch s!"duplicate process environment key '{key}'"
    keys := keys.push key

private def environmentArgs (environment : Array (String × String)) : Array String :=
  environment.map fun (key, value) => s!"{key}={value}"

private def runIsolated (launcher executable : FilePath)
    (environment : Array (String × String)) (args : Array String)
    (cwd : Option FilePath := none) : IO IO.Process.Output :=
  IO.Process.output {
    cmd := launcher.toString
    args := #["-i"] ++ environmentArgs environment ++ #[executable.toString] ++ args
    cwd
    inheritEnv := false
  }

def environmentIsolationSelfTest : IO Unit := do
  let (launcher, _statTool) ← resolveLauncher
  let environment := #[("PF_TEST_ALLOWED", "exact")]
  let output ← runIsolated launcher.path launcher.path environment #[]
  unless output.exitCode == 0 && output.stdout == "PF_TEST_ALLOWED=exact\n" &&
      output.stderr.isEmpty do
    mismatch s!"isolated child environment differed from its allowlist: {output.stdout}{output.stderr}"

def VerifiedTool.run (tool : VerifiedTool) (args : Array String)
    (cwd : Option FilePath := none) : IO IO.Process.Output := do
  validateProcessEnvironment tool.processEnvironment
  let (launcher, statTool) ← resolveLauncher
  unless launcher.path == tool.launcher do
    mismatch s!"process launcher is not the locked host env: {tool.launcher}"
  let executable ← verifyRegularFile tool.id tool.path tool.executableSha256 true
  verifyProtectedPath statTool tool.id executable .file
  let lock ← match loadLock with
    | .ok lock => pure lock
    | .error message => mismatch s!"invalid embedded lock: {message}"
  validateLockClosure lock
  let locked ← match lock.tools.find? (·.id == tool.id) with
    | some locked => pure locked
    | none => mismatch s!"unrecognized verified tool id '{tool.id}'"
  unless locked.executableSha256 == tool.executableSha256 do
    mismatch s!"{tool.id} VerifiedTool hash disagrees with the embedded lock"
  let root := executable.parent.getD "."
  unless executable == root / locked.executable do
    mismatch s!"{tool.id} executable is not at its locked bundle path"
  verifyBundleRoot statTool root lock.bundleFiles
  let expectedEnvironment ← lockedProcessEnvironment locked executable
  unless expectedEnvironment == tool.processEnvironment do
    mismatch s!"{tool.id} process environment disagrees with the embedded lock"
  runIsolated launcher.path executable tool.processEnvironment args cwd

def resolve (id : String) : IO VerifiedTool := do
  let lock ← match loadLock with
    | .ok lock => pure lock
    | .error message =>
        throw <| IO.userError s!"PF-TOOLCHAIN-MISMATCH: invalid embedded lock: {message}"
  validateLockClosure lock
  let tool ← match lock.tools.find? (·.id == id) with
    | some tool => pure tool
    | none => throwCompile <| .toolchainMissing id
  let candidate ← candidatePath tool
  unless ← candidate.pathExists do
    throwCompile <| .toolchainMissing candidate.toString
  let candidateRoot := candidate.parent.getD "."
  let candidateRootMetadata ← candidateRoot.symlinkMetadata
  unless candidateRootMetadata.type == .dir do
    mismatch s!"tool bundle root must be a real directory for {id}"
  let candidateMetadata ← candidate.symlinkMetadata
  unless candidateMetadata.type == .file do
    mismatch s!"executable must be a regular file for {id}"
  unless candidateMetadata.numLinks == 1 do
    mismatch s!"executable must have exactly one hard link for {id}"
  let realPath ← IO.FS.realPath candidate
  let binary ← IO.FS.readBinFile realPath
  let actualHash := Crypto.sha256Hex binary
  unless actualHash == tool.executableSha256 do
    throwCompile <| .toolchainMismatch id tool.executableSha256 actualHash
  let environment ← lockedProcessEnvironment tool realPath
  let (launcher, _statTool) ← resolveLauncher
  let verified : VerifiedTool := {
    id
    path := realPath
    launcher := launcher.path
    version := tool.version
    executableSha256 := actualHash
    processEnvironment := environment
  }
  let output ← verified.run tool.versionArgs
  unless output.exitCode == 0 do
    throwCompile <| .toolchainMismatch id tool.expectedVersion s!"exit {output.exitCode}"
  let observed := output.stdout ++ output.stderr
  unless observed.contains tool.expectedVersion do
    throwCompile <| .toolchainMismatch id tool.expectedVersion observed.trimAscii.copy
  return verified

end ProofForgeV2.CLI.Toolchain
