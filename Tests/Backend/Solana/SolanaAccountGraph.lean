import ProofForge.Backend.Solana.Manifest
import ProofForge.Backend.Solana.Plan
import ProofForge.Backend.Solana.Client

/-! Per-entrypoint Solana account graph and permission isolation regression. -/

namespace ProofForge.Tests.SolanaAccountGraph

open ProofForge.Backend.Solana.Extension
open ProofForge.Backend.Solana.Manifest
open ProofForge.Backend.Solana.Plan
open ProofForge.IR

def module : Module := {
  name := "AccountGraphProbe"
  state := #[]
  entrypoints := #[
    { name := "first", body := #[] },
    { name := "second", body := #[] }
  ]
}

def extensions : ProgramExtensions := {
  accountOrder := #["shared", "role", "first_only", "second_only"]
  accounts := #[
    { name := "shared", access := "readonly", signer := "none", owner := "any" },
    { name := "role", access := "writable", signer := "signer", owner := "any",
      entrypoint? := some "first" },
    { name := "role", access := "readonly", signer := "none", owner := "any",
      entrypoint? := some "second" },
    { name := "first_only", access := "writable", signer := "none", owner := "any",
      entrypoint? := some "first" },
    { name := "second_only", access := "readonly", signer := "signer", owner := "any",
      entrypoint? := some "second" }
  ]
}

def instructions : Array InstructionEntry :=
  buildInstructionsWithExtensions module extensions

def accountShape (instruction : InstructionEntry) : Array (String × Nat × Bool × Bool) :=
  instruction.accounts.map fun account =>
    (account.name, account.index, account.signer, account.writable)

def expectedFirst : Array (String × Nat × Bool × Bool) := #[
  ("shared", 0, false, false),
  ("role", 1, true, true),
  ("first_only", 2, false, true)
]

def expectedSecond : Array (String × Nat × Bool × Bool) := #[
  ("shared", 0, false, false),
  ("role", 1, false, false),
  ("second_only", 2, true, false)
]

def planAccountShape (accounts : Array SolanaAccountPlan) :
    Array (String × Nat × Bool × Bool) :=
  accounts.map fun account =>
    (account.name, account.index, account.signer, account.writable)

def scopedDefinitionsStaySeparate : Bool :=
  let first : DeclaredAccount := {
    name := "isolated"
    access := "writable"
    signer := "signer"
    owner := "any"
    entrypoint? := some "first"
  }
  let second : DeclaredAccount := {
    name := "isolated"
    access := "readonly"
    signer := "none"
    owner := "any"
    entrypoint? := some "second"
  }
  let parsed := ({} : ProgramExtensions).addDeclaredAccount first |>.addDeclaredAccount second
  parsed.accounts.size == 2 &&
    parsed.accounts[0]?.map (fun account =>
      account.entrypoint? == some "first" && account.signer == "signer" &&
        account.access == "writable") == some true &&
    parsed.accounts[1]?.map (fun account =>
      account.entrypoint? == some "second" && account.signer == "none" &&
        account.access == "readonly") == some true

def exactAccountCountCheckCount : Nat :=
  match ProofForge.Backend.Solana.SbpfAsm.lowerModuleCore module extensions with
  | .error _ => 0
  | .ok nodes => nodes.foldl (fun count node =>
      match node with
      | .instruction inst =>
          if inst.opcode == .jne && inst.dst == some .r2 &&
              inst.imm == some (.num 3) && inst.off == some (.sym "error_account_count") then
            count + 1
          else
            count
      | _ => count) 0

def check : IO Bool := do
  match instructions[0]?, instructions[1]? with
  | some first, some second =>
      let firstShape := accountShape first
      let secondShape := accountShape second
      if firstShape != expectedFirst then
        IO.eprintln s!"solana-account-graph: first={repr firstShape}, expected={repr expectedFirst}"
        return false
      if secondShape != expectedSecond then
        IO.eprintln s!"solana-account-graph: second={repr secondShape}, expected={repr expectedSecond}"
        return false
      let firstJson := ProofForge.Backend.Solana.Idl.instructionJson module extensions first
      let secondJson := ProofForge.Backend.Solana.Idl.instructionJson module extensions second
      if !firstJson.contains "first_only" || firstJson.contains "second_only" ||
          !secondJson.contains "second_only" || secondJson.contains "first_only" then
        IO.eprintln "solana-account-graph: IDL instruction account graphs are not scoped"
        return false
      let idl := ProofForge.Backend.Solana.Idl.renderWithInstructions module instructions extensions
      let client := ProofForge.Backend.Solana.Client.renderWithIdl idl
      if !client.contains firstJson || !client.contains secondJson then
        IO.eprintln "solana-account-graph: generated client did not embed scoped IDL graphs"
        return false
      if scopedDefinitionsStaySeparate != true then
        IO.eprintln "solana-account-graph: scoped account definitions merged permissions"
        return false
      if exactAccountCountCheckCount != 2 then
        IO.eprintln s!"solana-account-graph: exact account-count checks={exactAccountCountCheckCount}, expected 2"
        return false
      let firstEntrypoint := module.entrypoints[0]?
      let secondEntrypoint := module.entrypoints[1]?
      let firstPlan ←
        match firstEntrypoint with
        | none =>
            IO.eprintln "solana-account-graph: first entrypoint missing"
            return false
        | some entrypoint => match buildEntrypointPlan module extensions entrypoint 0 with
          | .ok plan => pure plan
          | .error err =>
              IO.eprintln s!"solana-account-graph: first plan failed: {err.render}"
              return false
      let secondPlan ←
        match secondEntrypoint with
        | none =>
            IO.eprintln "solana-account-graph: second entrypoint missing"
            return false
        | some entrypoint => match buildEntrypointPlan module extensions entrypoint 1 with
          | .ok plan => pure plan
          | .error err =>
              IO.eprintln s!"solana-account-graph: second plan failed: {err.render}"
              return false
      if planAccountShape firstPlan.accounts != expectedFirst ||
          planAccountShape secondPlan.accounts != expectedSecond then
        IO.eprintln "solana-account-graph: semantic plan account graphs drifted from manifest"
        return false
      return true
  | _, _ =>
      IO.eprintln "solana-account-graph: missing instruction graph"
      return false

end ProofForge.Tests.SolanaAccountGraph

def main : IO UInt32 := do
  if ← ProofForge.Tests.SolanaAccountGraph.check then
    IO.println "solana-account-graph: entrypoint roles and permissions isolated"
    return 0
  else
    return 1
