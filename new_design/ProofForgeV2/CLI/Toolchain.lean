import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
import ProofForgeV2.Core.Source

namespace ProofForgeV2.CLI.Toolchain

open Lean ProofForgeV2 System

structure LockedTool where
  id : String
  version : String
  sourceUrl : String
  platform : String
  executable : String
  defaultPath : String
  executableSha256 : String
  versionArgs : Array String
  expectedVersion : String
  licenseSpdx : String
  requiredByProfiles : Array String
  deriving FromJson, Repr

structure LockFile where
  schema : String
  tools : Array LockedTool
  deriving FromJson, Repr

structure VerifiedTool where
  id : String
  path : FilePath
  version : String
  executableSha256 : String
  deriving Repr

private def embeddedLock : String := include_str "../../toolchains.lock.json"

private def loadLock : Except String LockFile := do
  let lock : LockFile ← Json.parse embeddedLock >>= fromJson?
  unless lock.schema == "proof-forge.toolchains.v1" do
    throw s!"unsupported toolchain lock schema '{lock.schema}'"
  return lock

private def throwCompile (error : CompileError) : IO α :=
  throw <| IO.userError error.render

private def candidatePath (tool : LockedTool) : IO FilePath := do
  match ← IO.getEnv "PROOF_FORGE_TOOL_ROOT" with
  | none => pure <| FilePath.mk tool.defaultPath
  | some root =>
      let rootPath := FilePath.mk root
      unless rootPath.isAbsolute do
        throw <| IO.userError "PF-TOOLCHAIN-MISMATCH: PROOF_FORGE_TOOL_ROOT must be absolute"
      pure <| rootPath / tool.executable

def scrubbedEnvironment : Array (String × Option String) := #[
  ("PATH", none),
  ("LEAN_PATH", none),
  ("LD_PRELOAD", none),
  ("DYLD_INSERT_LIBRARIES", none),
  ("DYLD_LIBRARY_PATH", none),
  ("PYTHONPATH", none)
]

def resolve (id : String) : IO VerifiedTool := do
  let lock ← match loadLock with
    | .ok lock => pure lock
    | .error message =>
        throw <| IO.userError s!"PF-TOOLCHAIN-MISMATCH: invalid embedded lock: {message}"
  let tool ← match lock.tools.find? (·.id == id) with
    | some tool => pure tool
    | none => throwCompile <| .toolchainMissing id
  let candidate ← candidatePath tool
  unless ← candidate.pathExists do
    throwCompile <| .toolchainMissing candidate.toString
  let realPath ← IO.FS.realPath candidate
  let binary ← IO.FS.readBinFile realPath
  let actualHash := Crypto.sha256Hex binary
  unless actualHash == tool.executableSha256 do
    throwCompile <| .toolchainMismatch id tool.executableSha256 actualHash
  let output ← IO.Process.output {
    cmd := realPath.toString
    args := tool.versionArgs
    env := scrubbedEnvironment
  }
  unless output.exitCode == 0 do
    throwCompile <| .toolchainMismatch id tool.expectedVersion s!"exit {output.exitCode}"
  let observed := output.stdout ++ output.stderr
  unless observed.contains tool.expectedVersion do
    throwCompile <| .toolchainMismatch id tool.expectedVersion observed.trimAscii.copy
  return {
    id
    path := realPath
    version := tool.version
    executableSha256 := actualHash
  }

end ProofForgeV2.CLI.Toolchain
