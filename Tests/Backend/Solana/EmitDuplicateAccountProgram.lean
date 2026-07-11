import ProofForge.Backend.Solana.SbpfAsm

/-! Emit the dedicated three-role program used by the duplicate-account live gate. -/

namespace ProofForge.Tests.EmitDuplicateAccountProgram

open ProofForge.Backend.Solana.Asm
open ProofForge.Backend.Solana.Extension
open ProofForge.Backend.Solana.SbpfAsm
open ProofForge.IR

def module : Module := {
  name := "DuplicateAccountProgram"
  state := #[]
  entrypoints := #[{
    name := "probe"
    body := #[]
  }]
}

def extensions : ProgramExtensions := {
  accountOrder := #["first_role", "alias_role", "following_role"]
  accounts := #[
    { name := "first_role", access := "readonly", signer := "none", owner := "any" },
    { name := "alias_role", access := "readonly", signer := "none", owner := "any" },
    { name := "following_role", access := "readonly", signer := "none", owner := "any" }
  ]
}

def render : Except LowerError String := do
  let nodes ← lowerModuleCore module extensions
  .ok (renderNodes nodes)

end ProofForge.Tests.EmitDuplicateAccountProgram

def main (args : List String) : IO UInt32 := do
  let output := args.head?.getD "build/solana-duplicate-accounts/duplicate_accounts.s"
  match ProofForge.Tests.EmitDuplicateAccountProgram.render with
  | .error err =>
      IO.eprintln s!"solana-duplicate-accounts emitter: {err.render}"
      return 1
  | .ok source =>
      let path := System.FilePath.mk output
      if let some parent := path.parent then
        IO.FS.createDirAll parent
      IO.FS.writeFile path source
      IO.println s!"wrote {path}"
      return 0
