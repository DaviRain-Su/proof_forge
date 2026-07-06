import ProofForge.Cli.Quint

namespace Tests.Quint.CliEmit

def main : IO UInt32 := do
  for fixture in ProofForge.Cli.Quint.supportedFixtureIds do
    match ProofForge.Cli.Quint.fixtureModule? fixture with
    | none =>
        IO.eprintln s!"FAIL missing module for supported fixture {fixture}"
        return 1
    | some module =>
        if module.name.isEmpty then
          IO.eprintln s!"FAIL empty module name for fixture {fixture}"
          return 1
  IO.println "PASS"
  return 0

end Tests.Quint.CliEmit

def main : IO UInt32 := Tests.Quint.CliEmit.main