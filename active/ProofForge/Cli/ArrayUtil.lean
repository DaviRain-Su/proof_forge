namespace ProofForge.Cli

def dedupStrings (values : Array String) : Array String :=
  values.foldl (init := #[]) fun acc value =>
    if acc.contains value then acc else acc.push value

end ProofForge.Cli
