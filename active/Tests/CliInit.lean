import ProofForge.Cli.Scaffold

namespace ProofForge.Tests.CliInit

def require (cond : Bool) (msg : String) : IO Unit :=
  unless cond do throw <| IO.userError msg

def main : IO UInt32 := do
  match ProofForge.Cli.Scaffold.parseInitOptions ["my-counter", "--template", "portable-counter"] with
  | Except.ok opts =>
      require (opts.dir == "my-counter") "init dir parse"
      require (opts.templateId == "portable-counter") "init template parse"
  | Except.error err => throw <| IO.userError err
  match ProofForge.Cli.Scaffold.parseInitOptions ["--template", "unknown"] with
  | Except.ok _ => throw <| IO.userError "unknown template should fail"
  | Except.error err =>
      require (err.contains "unknown template") "unknown template error"
  let rendered := ProofForge.Cli.Scaffold.renderTemplateFile
    "name={{PACKAGE_NAME}};repo={{PROOF_FORGE_GIT_URL}}"
    "demo"
    "https://example.com/repo.git"
  require (rendered == "name=demo;repo=https://example.com/repo.git") "template substitution"
  IO.println "CliInit: ok"
  return 0

end ProofForge.Tests.CliInit

def main : IO UInt32 :=
  ProofForge.Tests.CliInit.main
