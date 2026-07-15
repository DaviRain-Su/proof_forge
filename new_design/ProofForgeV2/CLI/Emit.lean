import ProofForgeV2.Targets.Registry
import ProofForgeV2.CLI.Toolchain

namespace ProofForgeV2.CLI

open ProofForgeV2 Targets System

private def writeFileCreatingParent (path : FilePath) (contents : String) : IO Unit := do
  if let some parent := path.parent then
    IO.FS.createDirAll parent
  IO.FS.writeFile path contents

private def validArtifactName (value : String) : Bool :=
  match value.toList with
  | [] => false
  | first :: rest =>
      (first.isAlpha || first == '_') &&
        rest.all (fun char => char.isAlphanum || char == '_' || char == '-')

private def safeRelativePath (value : String) : Bool :=
  let path := FilePath.mk value
  !value.isEmpty && !path.isAbsolute &&
    !(path.components.contains "..") && !(path.components.contains ".") &&
    !value.contains "\u0000" && !value.contains "\r" && !value.contains "\n"

private def pathType? (path : FilePath) : IO (Option IO.FS.FileType) :=
  try
    return some (← path.symlinkMetadata).type
  catch _ =>
    return none

private def removePathIfPresent (path : FilePath) : IO Unit := do
  match ← pathType? path with
  | none => pure ()
  | some .dir => IO.FS.removeDirAll path
  | some _ => IO.FS.removeFile path

private partial def createSiblingStaging (parent : FilePath) (name : String)
    (pid attempt : Nat) : IO FilePath := do
  if attempt >= 128 then
    throw <| IO.userError "PF-OUTPUT-PATH: could not allocate an atomic staging directory"
  let candidate := parent / s!".{name}.staging-{pid}-{attempt}"
  try
    IO.FS.createDir candidate
    return candidate
  catch _ =>
    createSiblingStaging parent name pid (attempt + 1)

private def validateOutputSet (program : SemanticProgram) (output : OutputSet) : IO Unit := do
  unless output.manifest.sourceHash == program.sourceHash &&
      output.manifest.semanticHash == program.semanticHash do
    throw <| IO.userError "PF-OUTPUT-MANIFEST: materializer manifest does not bind the compiled program"
  unless validArtifactName program.name do
    throw <| IO.userError s!"PF-OUTPUT-PATH: unsafe program artifact name '{program.name}'"
  let mut paths : Array String := #[]
  for file in output.files do
    unless safeRelativePath file.path do
      throw <| IO.userError s!"PF-OUTPUT-PATH: unsafe artifact path '{file.path}'"
    if paths.contains file.path then
      throw <| IO.userError s!"PF-OUTPUT-PATH: duplicate artifact path '{file.path}'"
    paths := paths.push file.path

private structure Finalization where
  deployable : Bool
  extraFiles : Array String := #[]
  evidence : String

private def finalizeEvm (outputDir : FilePath) (programName : String) : IO Finalization := do
  let source := s!"{programName}.yul"
  let solc ← Toolchain.resolve "solc"
  let process ← IO.Process.output {
    cmd := solc.path.toString
    args := #["--strict-assembly", "--bin", source]
    cwd := some outputDir
    env := Toolchain.scrubbedEnvironment
  }
  if process.exitCode == 0 then
    let binary := (process.stdout.splitOn "Binary representation:\n").getLast!.trimAscii.copy
    if binary.isEmpty then
      throw <| IO.userError "PF-ARTIFACT-NONDEPLOYABLE: solc returned no bytecode"
    IO.FS.writeFile (outputDir / s!"{programName}.bin") (binary ++ "\n")
    pure {
      deployable := true
      extraFiles := #[s!"{programName}.bin"]
      evidence := s!"solc {solc.version} sha256={solc.executableSha256} completed successfully"
    }
  else
    throw <| IO.userError s!"PF-TOOLCHAIN-MISMATCH: solc failed\n{process.stderr}"

private def finalizeNear (outputDir : FilePath) (programName : String) : IO Finalization := do
  let source := s!"{programName}.wat"
  let target := s!"{programName}.wasm"
  let wat2wasm ← Toolchain.resolve "wat2wasm"
  let process ← IO.Process.output {
    cmd := wat2wasm.path.toString
    args := #[source, "-o", target]
    cwd := some outputDir
    env := Toolchain.scrubbedEnvironment
  }
  if process.exitCode == 0 then
    pure {
      deployable := true
      extraFiles := #[target]
      evidence := s!"wat2wasm {wat2wasm.version} sha256={wat2wasm.executableSha256} completed; runtime remains separate"
    }
  else
    throw <| IO.userError s!"PF-TOOLCHAIN-MISMATCH: wat2wasm failed\n{process.stderr}"

private def finalize (target : TargetId) (outputDir : FilePath) (programName : String) : IO Finalization :=
  match target with
  | .evm => finalizeEvm outputDir programName
  | .near => finalizeNear outputDir programName
  | .solana => pure {
      deployable := false
      evidence := "sBPF assembler is not present; .s and IDL are plan-level artifacts only"
    }
  | .noir => pure {
      deployable := false
      evidence := "nargo/bb are not present; Noir source and witness inputs were emitted without a proof"
    }
  | other => pure {
      deployable := false
      evidence := s!"{other} is research-only and has no V2 materializer"
    }

private def renderIntoStaging (target : TargetId) (program : SemanticProgram)
    (output : OutputSet) (stagingDir : FilePath) : IO OutputManifest := do
  for file in output.files do
    writeFileCreatingParent (stagingDir / file.path) file.contents
  let finalization ← finalize target stagingDir program.name
  for file in finalization.extraFiles do
    unless safeRelativePath file do
      throw <| IO.userError s!"PF-OUTPUT-PATH: unsafe finalized artifact path '{file}'"
  let manifest := {
    output.manifest with
    deployable := finalization.deployable
    files := output.manifest.files ++ finalization.extraFiles
  }
  IO.FS.writeFile (stagingDir / "manifest.json") (Targets.manifestJson manifest)
  let deployable := if manifest.deployable then "true" else "false"
  let evidence := "{\n" ++
    s!"  \"target\": \"{target}\",\n" ++
    s!"  \"sourceHash\": \"{program.sourceHash}\",\n" ++
    s!"  \"semanticHash\": \"{program.semanticHash}\",\n" ++
    s!"  \"deployable\": {deployable},\n" ++
    s!"  \"note\": \"{Targets.escapeJson finalization.evidence}\"\n" ++
    "}\n"
  IO.FS.writeFile (stagingDir / "evidence.json") evidence
  return manifest

def emitProgram (target : TargetId) (program : SemanticProgram) (outputDir : FilePath) : IO OutputManifest := do
  let output ← match Targets.materializeResult target program with
    | .ok output => pure output
    | .error error => throw <| IO.userError error.render
  validateOutputSet program output
  let name ← match outputDir.fileName with
    | some name => pure name
    | none => throw <| IO.userError "PF-OUTPUT-PATH: output directory must have a final component"
  unless name != "." && name != ".." && !name.isEmpty do
    throw <| IO.userError "PF-OUTPUT-PATH: unsafe output directory"
  let parentInput := outputDir.parent.getD "."
  IO.FS.createDirAll parentInput
  let parent ← IO.FS.realPath parentInput
  let destination := parent / name
  match ← pathType? destination with
  | some .symlink =>
      throw <| IO.userError "PF-OUTPUT-PATH: output directory cannot be a symbolic link"
  | some _ =>
      throw <| IO.userError
        s!"PF-OUTPUT-COLLISION: output already exists: {destination}; choose a fresh directory"
  | none => pure ()
  let pid ← IO.Process.getPID
  let staging ← createSiblingStaging parent name pid.toNat 0
  try
    let manifest ← renderIntoStaging target program output staging
    -- Recheck immediately before publish. This closes the cooperative writer
    -- race and ensures a build without an explicit future `--force` mode never
    -- replaces user data. A non-empty destination created by another process
    -- also makes the platform rename fail closed.
    if (← pathType? destination).isSome then
      throw <| IO.userError
        s!"PF-OUTPUT-COLLISION: output appeared during build: {destination}"
    IO.FS.rename staging destination
    return manifest
  catch error =>
    removePathIfPresent staging
    throw error

end ProofForgeV2.CLI
