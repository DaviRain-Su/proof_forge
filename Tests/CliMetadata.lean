import ProofForge.Cli.Metadata

namespace ProofForge.Tests.CliMetadata

def main : IO UInt32 := do
  let args := ["--target", "psy-dpn", "--fixture", "counter"]
  match ProofForge.Cli.Metadata.parseMetadataOptions args with
  | .error msg =>
      IO.eprintln s!"parse error: {msg}"
      return 1
  | .ok opts =>
      let code ← ProofForge.Cli.Metadata.metadataCommand opts
      if code != 0 then
        IO.eprintln "metadata command failed"
        return 1
      IO.println "ok: CLI metadata command returned 0"
      return 0

end ProofForge.Tests.CliMetadata

def main : IO UInt32 :=
  ProofForge.Tests.CliMetadata.main
