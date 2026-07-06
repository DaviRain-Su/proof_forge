import ProofForge.Cli.Metadata
import Lean.Data.Json

namespace ProofForge.Tests.CliMetadata

def assert (cond : Bool) (msg : String) : IO Unit :=
  if cond then
    IO.println s!"ok: {msg}"
  else
    throw <| IO.userError s!"fail: {msg}"

def main : IO UInt32 := do
  let outPath := System.FilePath.mk "build" / "cli-metadata-test.json"
  IO.FS.createDirAll (outPath.parent.getD ".")
  let args := ["--target", "psy-dpn", "--fixture", "counter", "--output", outPath.toString]
  match ProofForge.Cli.Metadata.parseMetadataOptions args with
  | .error msg =>
      IO.eprintln s!"parse error: {msg}"
      return 1
  | .ok opts =>
      let code ← ProofForge.Cli.Metadata.metadataCommand opts
      if code != 0 then
        IO.eprintln "metadata command failed"
        return 1
      let jsonStr ← IO.FS.readFile outPath
      match Lean.Json.parse jsonStr with
      | .error msg =>
          IO.eprintln s!"output is not valid JSON: {msg}"
          return 1
      | .ok json =>
          match json.getObj? with
          | .error msg =>
              IO.eprintln s!"output JSON is not an object: {msg}"
              return 1
          | .ok obj =>
              for key in ["targetId", "moduleName", "entrypoints", "capabilities"] do
                if !obj.contains key then
                  IO.eprintln s!"missing key: {key}"
                  return 1
              IO.println "ok: CLI metadata output contains required keys"
              return 0

end ProofForge.Tests.CliMetadata

def main : IO UInt32 :=
  ProofForge.Tests.CliMetadata.main
