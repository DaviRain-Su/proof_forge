import ProofForge.Backend.Solana.Package
import ProofForge.Contract.Builder
import ProofForge.Solana

namespace ProofForge.Tests.SolanaPdaSeeds

open ProofForge.Contract.Builder
open ProofForge.Solana

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then
    pure ()
  else
    throw <| IO.userError message

def contains (haystack needle : String) : Bool :=
  haystack.contains needle

def pdaOnlySpec : ProofForge.Contract.ContractSpec :=
  build "SolanaPdaSeedProbe" do
    scalarState "nonce" .u64

    pdaAccount "vault" #[literalSeed "vault", accountSeed "authority"]
      (bump? := some "vault_bump")
      (account? := some "vault_account")

    entrySelectorWithParams "touch" "04" #[("vault_bump", .u64)] .unit do
      derivePda "vault" #[literalSeed "vault", accountSeed "authority"]
        (bump? := some "vault_bump")
        (account? := some "vault_account")
      effect (storageScalarWrite "nonce" (localVar "vault_bump"))

/-- Signer PDA + portable peer crosscall → invoke_signed with seed packing.
Declared peer id is required for Solana PortableHonesty account inference. -/
def portablePdaRemoteSpec : ProofForge.Contract.ContractSpec :=
  let s := build "SolanaPortablePdaRemote" do
    scalarState "nonce" .u64

    pdaAccount "vault" #[literalSeed "vault", accountSeed "authority"]
      (bump? := some "vault_bump")
      (account? := some "vault_account")
      (isSigner := true)

    entrySelectorWithParams "call_remote" "05"
        #[("target", .u64), ("method", .u64), ("vault_bump", .u64)] .u64 do
      derivePda "vault" #[literalSeed "vault", accountSeed "authority"]
        (bump? := some "vault_bump")
        (account? := some "vault_account")
        (isSigner := true)
      ret (ProofForge.IR.Expr.crosscallInvoke
        (localVar "target") (localVar "method") #[])
  { s with module := { s.module with nearCrosscallStrings := #["portable.callee"] } }

def main : IO UInt32 := do
  match ProofForge.Backend.Solana.Package.renderPackageForSpec "pda-seeds" pdaOnlySpec with
  | .ok pkg =>
      let some asmFile := pkg.files.find? (fun file => file.path == pkg.asmPath)
        | throw <| IO.userError "pda-seeds package missing sBPF assembly"
      let some manifestFile := pkg.files.find? (fun file => file.path == "manifest.toml")
        | throw <| IO.userError "pda-seeds package missing manifest.toml"
      let asm := asmFile.contents
      let manifest := manifestFile.contents
      require (contains manifest "{ name = \"nonce\", index = 0, signer = false, writable = true, owner = \"program\" },")
        "manifest missing state account schema"
      require (contains manifest "{ name = \"vault_account\", index = 1, signer = false, writable = true, owner = \"program\" },")
        "manifest missing PDA account schema"
      require (contains manifest "{ name = \"authority\", index = 2, signer = false, writable = false, owner = \"any\" }")
        "manifest missing PDA account-seed source account schema"
      require (contains manifest "typed_seeds = [")
        "manifest missing PDA typed seed descriptors"
      require (contains manifest "{ kind = \"account\", value = \"authority\" },")
        "manifest missing authority account seed descriptor"
      require (contains manifest "{ kind = \"bump\", value = \"vault_bump\" }")
        "manifest missing vault_bump seed descriptor"
      require (contains manifest "{ name = \"vault_bump\", type = \"U64\", offset = 1, byte_size = 8, encoding = \"le-u64\" }")
        "manifest missing vault_bump instruction parameter schema"
      require (contains asm "solana.pda.seed vault[1] account authority pubkey")
        "assembly missing authority pubkey PDA seed packing"
      require (!contains asm "account authority missing placeholder=zero")
        "authority account seed should not fall back to zero placeholder"
      require (contains asm "solana.pda.seed vault[2] bump vault_bump from instruction param")
        "assembly missing instruction-parameter bump seed packing"
      require (!contains asm "bump vault_bump missing placeholder=255")
        "vault_bump should bind to instruction parameter, not placeholder"
      require (contains asm "mov64 r7, r9")
        "assembly missing saved instruction-data pointer use for bump seed"
      require (contains asm "ldxb r3, [r7+")
        "assembly missing byte load for instruction-parameter bump seed"
      require (contains asm "stxb [r5+0], r3")
        "assembly missing bump byte copy into PDA seed buffer"
      require (contains asm "solana.pda.validate vault account vault_account")
        "assembly missing PDA account pubkey validation"
  | .error err =>
      throw <| IO.userError s!"Solana PDA seed package render failed: {err.render}"

  match ProofForge.Backend.Solana.Package.renderPackageForSpec
      "portable-pda-remote" portablePdaRemoteSpec with
  | .ok pkg =>
      let some asmFile := pkg.files.find? (fun file => file.path == pkg.asmPath)
        | throw <| IO.userError "portable-pda-remote package missing sBPF assembly"
      let asm := asmFile.contents
      require (contains asm "sol_invoke_signed_c")
        "portable PDA remote must emit sol_invoke_signed_c"
      require (contains asm "signers=1 (PDA authority)" || contains asm "signers=1")
        "portable CPI with signer PDA must pass signers=1"
      require (contains asm "solana.cpi.signer_seed portable_crosscall")
        "portable CPI must pack signer seeds from signer PDA"
      require (contains asm "literal" || contains asm "\"vault\"" ||
          contains asm "account authority")
        "portable CPI signer seeds should include vault PDA seeds"
      require (contains asm "bump vault_bump" || contains asm "bump:")
        "portable CPI signer seeds should include vault_bump"
  | .error err =>
      throw <| IO.userError s!"Solana portable PDA remote package render failed: {err.render}"

  -- Pure peer CPI (no PDA signers): empty AccountMeta pack (PF-P2-03).
  -- Outer host accounts are not forwarded; method+args ride in ix data.
  -- Selective pack activates only when PDA signer seeds are present (above).
  let purePeerSpec : ProofForge.Contract.ContractSpec :=
    let s := build "SolanaPurePeerCpi" do
      scalarState "nonce" .u64
      writableAccountConstraint "authority"
      readonlyAccountConstraint "spectator"
      writableAccountConstraint "vault_account" (owner := "program")
      entrySelectorWithParams "call_remote" "06"
          #[("target", .u64), ("method", .u64)] .u64 do
        ret (ProofForge.IR.Expr.crosscallInvoke
          (localVar "target") (localVar "method") #[])
    { s with module := { s.module with nearCrosscallStrings := #["portable.callee"] } }
  match ProofForge.Backend.Solana.Package.renderPackageForSpec
      "pure-peer-cpi-accounts" purePeerSpec with
  | .ok pkg =>
      let some asmFile := pkg.files.find? (fun file => file.path == pkg.asmPath)
        | throw <| IO.userError "pure-peer package missing sBPF assembly"
      let asm := asmFile.contents
      require (contains asm "empty AccountMeta pack" || contains asm "accounts=0")
        "pure peer CPI must use empty AccountMeta pack (no host-account forward)"
      require (contains asm "sol_invoke_signed_c")
        "pure peer portable remote must still invoke"
      require (contains asm "sol_get_return_data")
        "pure peer CPI must decode return data"
  | .error err =>
      throw <| IO.userError s!"pure peer CPI accounts package render failed: {err.render}"

  IO.println "solana-pda-seeds: ok (derive + portable signed CPI + pure-peer empty pack)"  return 0

end ProofForge.Tests.SolanaPdaSeeds

def main : IO UInt32 :=
  ProofForge.Tests.SolanaPdaSeeds.main
