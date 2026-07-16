import ProofForge.Backend.Solana.Package
import ProofForge.Contract.Builder
import ProofForge.Contract.Source.Solana.Legacy
import ProofForge.Target.Adapter
import ProofForge.Target.Registry

namespace ProofForge.Tests.SolanaAccountConstraints

open ProofForge.Target

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then
    pure ()
  else
    throw <| IO.userError message

def contains (haystack needle : String) : Bool :=
  haystack.contains needle

def ownerSpec : ProofForge.Contract.ContractSpec :=
  ProofForge.Contract.Builder.build "SolanaOwnerConstraints" do
    ProofForge.Contract.Builder.scalarState "counter" .u64
    ProofForge.Contract.Source.Solana.Legacy.readonlyAccountConstraint "token_program" (owner := "executable")
    ProofForge.Contract.Source.Solana.Legacy.writableAccountConstraint "token_account" (owner := "token_program")
    ProofForge.Contract.Builder.entry "touch" do
      ProofForge.Contract.Builder.effect
        (ProofForge.Contract.Builder.storageScalarAssignOp "counter"
          ProofForge.IR.AssignOp.add
          (ProofForge.Contract.Builder.u64 1))

def missingOwnerSpec : ProofForge.Contract.ContractSpec :=
  ProofForge.Contract.Builder.build "SolanaMissingOwnerConstraint" do
    ProofForge.Contract.Builder.scalarState "counter" .u64
    ProofForge.Contract.Source.Solana.Legacy.writableAccountConstraint "token_account" (owner := "missing_program")
    ProofForge.Contract.Builder.entry "touch" do
      ProofForge.Contract.Builder.effect
        (ProofForge.Contract.Builder.storageScalarAssignOp "counter"
          ProofForge.IR.AssignOp.add
          (ProofForge.Contract.Builder.u64 1))

def main : IO UInt32 := do
  let plan ←
    match resolveSpec solanaSbpfAsm ownerSpec with
    | .ok plan => pure plan
    | .error err => throw <| IO.userError s!"Solana account constraints routing failed: {err.render}"

  let pkg ←
    match ProofForge.Backend.Solana.Package.renderPackageForSpec "solana-owner-constraints" ownerSpec with
    | .ok pkg => pure pkg
    | .error err => throw <| IO.userError s!"Solana owner-constraint package render failed: {err.render}"

  let some manifestFile := pkg.files.find? (fun file => file.path == "manifest.toml")
    | throw <| IO.userError "owner-constraint package missing manifest.toml"
  let some idlFile := pkg.files.find? (fun file => file.path == pkg.idlPath)
    | throw <| IO.userError "owner-constraint package missing IDL"
  let some asmFile := pkg.files.find? (fun file => file.path == pkg.asmPath)
    | throw <| IO.userError "owner-constraint package missing assembly"

  require (plan.capabilities.any (fun c => c == .accountExplicit))
    "Solana owner-constraint plan missing account.explicit capability"
  require (contains manifestFile.contents "{ name = \"counter\", index = 0, signer = false, writable = true, owner = \"program\" },")
    "manifest missing program-owned state account"
  require (contains manifestFile.contents "{ name = \"token_program\", index = 1, signer = false, writable = false, owner = \"executable\" },")
    "manifest missing executable owner constraint"
  require (contains manifestFile.contents "{ name = \"token_account\", index = 2, signer = false, writable = true, owner = \"token_program\" }")
    "manifest missing named-owner account constraint"
  require (contains idlFile.contents "\"owner\": \"executable\"")
    "IDL missing executable owner constraint"
  require (contains idlFile.contents "\"owner\": \"token_program\"")
    "IDL missing named-owner account constraint"
  require (contains asmFile.contents "account.validation[0:counter]: owner=program")
    "assembly missing current-program owner validation"
  require (contains asmFile.contents "account.validation[1:token_program]: owner=executable")
    "assembly missing executable owner validation"
  require (contains asmFile.contents "account.validation[2:token_account]: writable=true")
    "assembly missing writable validation for token_account"
  require (contains asmFile.contents "account.validation[2:token_account]: owner=token_program")
    "assembly missing named-owner validation"
  require (contains asmFile.contents "error_owner")
    "assembly missing owner error path"

  match ProofForge.Backend.Solana.Package.renderPackageForSpec "solana-missing-owner" missingOwnerSpec with
  | .ok _ => throw <| IO.userError "missing owner account unexpectedly lowered"
  | .error err =>
      require (contains err.render "unknown Solana owner account `missing_program`")
        s!"unexpected missing-owner diagnostic: {err.render}"

  IO.println "solana-account-constraints: ok"
  return 0

end ProofForge.Tests.SolanaAccountConstraints

def main : IO UInt32 :=
  ProofForge.Tests.SolanaAccountConstraints.main
