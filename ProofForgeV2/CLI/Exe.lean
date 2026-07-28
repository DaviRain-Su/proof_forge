/-
  lean_exe root for `proof-forge-next`.

  Keeps top-level `main` out of `ProofForgeV2.CLI.Main` so the product CLI
  library surface (`ProofForgeV2.CLI.run`) can be imported by tests without
  redeclaring `main` (Fast/full test roots also define `main`).
-/
import ProofForgeV2.CLI.Main

unsafe def main (args : List String) : IO Unit := ProofForgeV2.CLI.run args
