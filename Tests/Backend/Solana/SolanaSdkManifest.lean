import ProofForge.Backend.Solana.Manifest
import ProofForge.Backend.Solana.Package
import ProofForge.Backend.Solana.Idl
import ProofForge.IR.Examples.ErrorRefProbe
import Examples.Backend.Solana.Contracts.Vault
import ProofForge.Target.Adapter
import ProofForge.Target.Registry

namespace ProofForge.Tests.SolanaSdkManifest

open ProofForge.Target

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then
    pure ()
  else
    throw <| IO.userError message

def contains (haystack needle : String) : Bool :=
  haystack.contains needle

def main : IO UInt32 := do
  let spec := Examples.Backend.Solana.Contracts.Vault.spec
  let plan ←
    match resolveSpec solanaSbpfAsm spec with
    | .ok plan => pure plan
    | .error err => throw <| IO.userError s!"Solana Vault SDK routing failed: {err.render}"

  let manifest := ProofForge.Backend.Solana.Manifest.renderManifestWithPlan spec.module plan
  let idl := ProofForge.Backend.Solana.Idl.renderWithPlan spec.module plan
  require (contains manifest "[[solana.account]]") "manifest missing Solana declared account section"
  require (contains idl "\"schema\": \"proof-forge.solana.idl.v0\"")
    "IDL missing schema marker"
  require (contains idl "\"name\": \"SolanaVault\"")
    "IDL missing program name"
  require (contains idl "\"target\": \"solana-sbpf-asm\"")
    "IDL missing target"
  require (contains idl "\"instructions\"")
    "IDL missing instruction list"
  require (contains idl "\"name\": \"touch\"")
    "IDL missing touch instruction"
  require (contains idl "\"accounts\"")
    "IDL missing account schema"
  require (contains idl "\"name\": \"vault_account\"")
    "IDL missing vault_account"
  require (contains idl "\"owner\": \"program\"")
    "IDL missing program owner constraint"
  require (contains idl "\"pdas\"")
    "IDL missing PDA list"
  require (contains idl "\"typedSeeds\"")
    "IDL missing typed PDA seeds"
  require (contains idl "\"cpis\"")
    "IDL missing CPI list"
  require (contains idl "\"name\": \"token_transfer\"")
    "IDL missing token_transfer CPI"
  require (contains idl "\"dataLayout\": \"spl-token.transfer_checked\"")
    "IDL missing SPL Token data layout"
  require (contains idl "\"entrypointActions\"")
    "IDL missing entrypoint action metadata"
  require (contains idl "\"errors\": []")
    "IDL missing empty portable error catalogue"
  require (contains manifest "name = \"vault_account\"\naccess = \"writable\"\nsigner = \"none\"\nowner = \"program\"")
    "manifest missing declared vault_account constraints"
  require (contains manifest "name = \"spl_token\"\naccess = \"readonly\"\nsigner = \"none\"\nowner = \"executable\"")
    "manifest missing declared spl_token executable constraint"
  require (contains manifest "[[solana.allocator]]") "manifest missing Solana allocator section"
  require (contains manifest "kind = \"bump\"") "manifest missing bump allocator kind"
  require (contains manifest "model = \"downward-bump\"") "manifest missing bump allocator model"
  require (contains manifest "heap_start = \"0x300000000\"") "manifest missing allocator heap start"
  require (contains manifest "heap_bytes = 32768") "manifest missing allocator heap size"
  require (contains manifest "{ name = \"nonce\", index = 0, signer = false, writable = true, owner = \"program\" },")
    "manifest missing state account schema"
  require (contains manifest "{ name = \"vault_account\", index = 1, signer = false, writable = true, owner = \"program\" },")
    "manifest missing PDA account schema"
  require (contains manifest "{ name = \"source\", index = 2, signer = false, writable = true, owner = \"any\" },")
    "manifest missing source account schema"
  require (contains manifest "{ name = \"mint\", index = 3, signer = false, writable = false, owner = \"any\" },")
    "manifest missing mint account schema"
  require (contains manifest "{ name = \"destination\", index = 4, signer = false, writable = true, owner = \"any\" },")
    "manifest missing destination account schema"
  require (contains manifest "{ name = \"authority\", index = 5, signer = false, writable = false, owner = \"any\" },")
    "manifest missing authority account schema"
  require (contains manifest "{ name = \"spl_token\", index = 6, signer = false, writable = false, owner = \"executable\" }")
    "manifest missing SPL Token program account schema"
  require (contains manifest "min_data_len = 1") "manifest missing default instruction-data minimum length"
  require (contains manifest "params = []") "manifest missing empty instruction parameter schema"
  require (contains manifest "[[solana.pda]]") "manifest missing Solana PDA section"
  require (contains manifest "name = \"vault\"") "manifest missing PDA name"
  require (contains manifest "seeds = [\"vault\", \"authority\"]") "manifest missing PDA seeds"
  require (contains manifest "typed_seeds = [") "manifest missing PDA typed seeds"
  require (contains manifest "{ kind = \"literal\", value = \"vault\" },")
    "manifest missing literal PDA seed descriptor"
  require (contains manifest "{ kind = \"account\", value = \"authority\" },")
    "manifest missing account PDA seed descriptor"
  require (contains manifest "{ kind = \"bump\", value = \"vault_bump\" }")
    "manifest missing bump PDA seed descriptor"
  require (contains manifest "bump = \"vault_bump\"") "manifest missing PDA bump"
  require (contains manifest "account = \"vault_account\"") "manifest missing PDA account"
  require (contains manifest "[[solana.cpi]]") "manifest missing Solana CPI section"
  require (contains manifest "program = \"spl_token\"") "manifest missing CPI program"
  require (contains manifest "protocol = \"spl-token\"") "manifest missing CPI protocol"
  require (contains manifest "instruction = \"transfer_checked\"") "manifest missing CPI instruction"
  require (contains manifest "signed = true") "manifest missing signed CPI marker"
  require (contains manifest "data_layout = \"spl-token.transfer_checked\"")
    "manifest missing CPI data layout"
  require (contains manifest "amount_source = \"amount\"")
    "manifest missing CPI amount source"
  require (contains manifest "decimals = \"9\"")
    "manifest missing CPI decimals"
  require (contains manifest "{ name = \"source\", access = \"writable\", signer = \"none\" }")
    "manifest missing writable source account"
  require (contains manifest "{ name = \"source\", access = \"writable\", signer = \"none\" },")
    "manifest missing comma after non-final CPI account"
  require (contains manifest "{ name = \"mint\", access = \"readonly\", signer = \"none\" },")
    "manifest missing readonly mint account"
  require (contains manifest "{ name = \"authority\", access = \"readonly\", signer = \"pda-signer\" }")
    "manifest missing PDA signer authority account"
  require (contains manifest "signer_seeds = [\"vault\", \"vault_bump\"]")
    "manifest missing CPI signer seeds"
  require (contains manifest "[[solana.entrypoint_pda]]")
    "manifest missing entrypoint PDA action section"
  require (contains manifest "entrypoint = \"touch\"")
    "manifest missing touch entrypoint action"
  require (contains manifest "pda = \"vault\"")
    "manifest missing touch PDA action"
  require (contains manifest "[[solana.entrypoint_cpi]]")
    "manifest missing entrypoint CPI action section"
  require (contains manifest "cpi = \"token_transfer\"")
    "manifest missing touch CPI action"

  match ProofForge.Backend.Solana.Package.renderPackageForSpec "solana-vault" spec with
  | .ok pkg =>
      let some manifestFile := pkg.files.find? (fun file => file.path == "manifest.toml")
        | throw <| IO.userError "package missing manifest.toml"
      let some idlFile := pkg.files.find? (fun file => file.path == pkg.idlPath)
        | throw <| IO.userError "package missing proof-forge-idl.json"
      let some clientFile := pkg.files.find? (fun file => file.path == pkg.clientPath)
        | throw <| IO.userError "package missing proof-forge-client.ts"
      let some asmFile := pkg.files.find? (fun file => file.path == pkg.asmPath)
        | throw <| IO.userError "package missing sBPF assembly"
      require (pkg.idlPath == "proof-forge-idl.json")
        "package IDL path mismatch"
      require (pkg.clientPath == "proof-forge-client.ts")
        "package client path mismatch"
      require (contains idlFile.contents "\"schema\": \"proof-forge.solana.idl.v0\"")
        "package IDL missing schema marker"
      require (contains idlFile.contents "\"instructions\"")
        "package IDL missing instruction list"
      require (contains idlFile.contents "\"name\": \"touch\"")
        "package IDL missing touch instruction"
      require (contains idlFile.contents "\"name\": \"token_transfer\"")
        "package IDL missing token_transfer CPI"
      require (contains idlFile.contents "\"errors\": []")
        "package IDL missing empty portable error catalogue"
      require (contains clientFile.contents "export const IDL = ")
        "package client missing embedded IDL"
      require (contains clientFile.contents "export const ERRORS = IDL.errors")
        "package client missing embedded error catalogue export"
      require (contains clientFile.contents "errorBySolanaCustomCode")
        "package client missing Solana custom error helper"
      require (contains clientFile.contents "encodeInstructionData")
        "package client missing instruction-data encoder"
      require (contains clientFile.contents "accountMetas")
        "package client missing account meta builder"
      require (contains clientFile.contents "createInstruction")
        "package client missing TransactionInstruction factory"
      require (contains manifestFile.contents "[[solana.pda]]")
        "package manifest missing Solana PDA section"
      require (contains manifestFile.contents "[[solana.account]]")
        "package manifest missing Solana declared account section"
      require (contains manifestFile.contents "name = \"source\"\naccess = \"writable\"\nsigner = \"none\"\nowner = \"any\"")
        "package manifest missing declared source writable account"
      require (contains manifestFile.contents "typed_seeds = [")
        "package manifest missing PDA typed seeds"
      require (contains manifestFile.contents "[[solana.allocator]]")
        "package manifest missing Solana allocator section"
      require (contains manifestFile.contents "heap_start = \"0x300000000\"")
        "package manifest missing allocator heap start"
      require (contains manifestFile.contents "[[solana.cpi]]")
        "package manifest missing Solana CPI section"
      require (contains manifestFile.contents "protocol = \"spl-token\"")
        "package manifest missing CPI protocol"
      require (contains manifestFile.contents "{ name = \"vault_account\", index = 1, signer = false, writable = true, owner = \"program\" },")
        "package manifest missing PDA account schema"
      require (contains manifestFile.contents "{ name = \"spl_token\", index = 6, signer = false, writable = false, owner = \"executable\" }")
        "package manifest missing SPL Token program account schema"
      require (contains manifestFile.contents "min_data_len = 1")
        "package manifest missing default instruction-data minimum length"
      require (contains manifestFile.contents "params = []")
        "package manifest missing empty instruction parameter schema"
      require (contains asmFile.contents "solana.allocator runtime: kind=bump model=downward-bump heap_start=0x300000000 heap_bytes=32768")
        "package assembly missing runtime allocator metadata"
      require (contains asmFile.contents "instruction_data.length >= 1")
        "package assembly missing instruction-data tag length check"
      require (contains asmFile.contents "account.validation[1:vault_account]: owner=program")
        "package assembly missing PDA owner validation"
      require (contains asmFile.contents "account.validation[2:source]: writable=true")
        "package assembly missing source writable validation"
      require (contains asmFile.contents "account.validation[4:destination]: writable=true")
        "package assembly missing destination writable validation"
      require (contains asmFile.contents "sol_pda_derive_vault:")
        "package assembly missing PDA helper label"
      require (contains asmFile.contents "solana.pda.seed vault[0] \"vault\"")
        "package assembly missing static vault PDA seed packing"
      require (contains asmFile.contents "stb [r5+0], 118")
        "package assembly missing vault seed byte store"
      require (contains asmFile.contents "solana.pda.seed vault[1] account authority pubkey")
        "package assembly missing authority account PDA seed packing"
      -- Entry params (amount, vault_bump) bind into valueBindings — no silent zeros.
      require (contains asmFile.contents "solana.pda.seed vault[2] bump vault_bump from instruction param")
        "package assembly missing vault_bump instruction-param packing"
      require (!contains asmFile.contents "placeholder=zero")
        "package assembly must not pack zero PDA/signer seed placeholders"
      require (!contains asmFile.contents "placeholder=0")
        "package assembly must not pack silent zero CPI value placeholders"
      require (!contains asmFile.contents "placeholder=255")
        "package assembly must not pack 255 bump placeholders"
      require (contains asmFile.contents "stxdw [r6+0], r5")
        "package assembly missing PDA seed slice ptr store"
      require (contains asmFile.contents "stxdw [r6+8], r3")
        "package assembly missing PDA seed slice length store"
      require (contains asmFile.contents "mov64 r9, r3")
        "package assembly missing entry instruction-data pointer register save"
      require (contains asmFile.contents "mov64 r3, r9")
        "package assembly missing dynamic program id pointer calculation"
      require (contains asmFile.contents "call sol_create_program_address")
        "package assembly missing PDA syscall"
      require (contains asmFile.contents "PDA result stored at stack offset 64")
        "package assembly missing PDA result buffer marker"
      require (contains asmFile.contents "solana.pda.validate vault account vault_account")
        "package assembly missing PDA result account validation"
      require (contains asmFile.contents "call sol_pda_derive_vault")
        "package assembly missing entrypoint PDA helper call"
      require (contains asmFile.contents "sol_cpi_token_transfer:")
        "package assembly missing CPI helper label"
      require (contains asmFile.contents "solana.cpi.program_id spl_token TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA")
        "package assembly missing hard-coded SPL Token program id"
      require (contains asmFile.contents "solana.cpi.account_meta source key_ptr account[2]")
        "package assembly missing source account meta binding"
      require (contains asmFile.contents "solana.cpi.account_info source account[2]")
        "package assembly missing source account info binding"
      require (contains asmFile.contents "solana.cpi.account_info destination account[4]")
        "package assembly missing destination account info binding"
      require (contains asmFile.contents "solana.cpi.data spl-token.transfer_checked: u8 instruction=12, u64 amount, u8 decimals=9")
        "package assembly missing SPL Token transfer_checked data packing"
      require (contains asmFile.contents "solana.cpi.value amount from instruction param amount"
          || contains asmFile.contents "from instruction param amount")
        "package assembly missing bound amount instruction-param packing"
      require (contains asmFile.contents "stb [r8+0], 12")
        "package assembly missing SPL Token transfer_checked discriminator store"
      require (contains asmFile.contents "stb [r8+9], 9")
        "package assembly missing SPL Token transfer_checked decimals store"
      require (contains asmFile.contents "call sol_invoke_signed_c")
        "package assembly missing CPI syscall"
      require (contains asmFile.contents "call sol_cpi_token_transfer")
        "package assembly missing entrypoint CPI helper call"
  | .error err =>
      throw <| IO.userError s!"Solana SDK package render failed: {err.render}"

  let errorModule := ProofForge.IR.Examples.ErrorRefProbe.module
  let errorIdl := ProofForge.Backend.Solana.Idl.render errorModule
  require (contains errorIdl "\"errors\": [")
    "ErrorRefProbe Solana IDL missing portable errors catalogue"
  require (contains errorIdl "\"assertionId\": 1")
    "ErrorRefProbe Solana IDL missing assertion id 1"
  require (contains errorIdl "\"userCode\": \"Counter::Overflow\"")
    "ErrorRefProbe Solana IDL missing Counter::Overflow user code"
  require (contains errorIdl "\"entrypoints\": [\"guarded_increment\"]")
    "ErrorRefProbe Solana IDL missing guarded_increment error ownership"
  require (contains errorIdl "\"assertionId\": 2")
    "ErrorRefProbe Solana IDL missing assertion id 2"
  require (contains errorIdl "\"userCode\": \"Counter::ExactMatch\"")
    "ErrorRefProbe Solana IDL missing Counter::ExactMatch user code"
  let errorClient := ProofForge.Backend.Solana.Client.render errorModule
  require (contains errorClient "export const ERRORS = IDL.errors")
    "ErrorRefProbe Solana client missing IDL error export"
  require (contains errorClient "Counter::Overflow")
    "ErrorRefProbe Solana client missing embedded Counter::Overflow error"
  require (contains errorClient "errorByAssertionId")
    "ErrorRefProbe Solana client missing assertion-id helper"
  require (contains errorClient "errorBySolanaCustomCode")
    "ErrorRefProbe Solana client missing custom error helper"
  require (contains errorClient "0x100000000n")
    "ErrorRefProbe Solana client missing encoded custom-error normalization"

  IO.println "solana-sdk-manifest: ok"
  return 0

end ProofForge.Tests.SolanaSdkManifest

def main : IO UInt32 :=
  ProofForge.Tests.SolanaSdkManifest.main
