import ProofForge.Backend.Solana.Package
import ProofForge.Contract.Builder
import ProofForge.Solana
import ProofForge.Solana.Examples.AssociatedTokenCpi
import ProofForge.Solana.Examples.MemoCpi
import ProofForge.Solana.Examples.SplTokenAuthorityCpi
import ProofForge.Solana.Examples.SplToken2022Cpi
import ProofForge.Solana.Examples.SplToken2022PausableCpi
import ProofForge.Solana.Examples.SplToken2022TransferHook
import ProofForge.Solana.Examples.SplTokenCloseAccountCpi
import ProofForge.Solana.Examples.SplTokenOpsCpi

set_option maxRecDepth 2048

namespace ProofForge.Tests.SolanaCpiPacking

open ProofForge.Contract.Builder
open ProofForge.Solana

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then
    pure ()
  else
    throw <| IO.userError message

def contains (haystack needle : String) : Bool :=
  haystack.contains needle

def systemTransferSpec : ProofForge.Contract.ContractSpec :=
  build "SolanaSystemCpi" do
    scalarState "nonce" .u64
    scalarState "lamports" .u64

    systemTransfer
      "lamport_transfer"
      "payer"
      "recipient"
      "lamports"

    entrySelector "transfer" "01" do
      invokeSystemTransfer
        "lamport_transfer"
        "payer"
        "recipient"
        "lamports"
      effect (storageScalarWrite "nonce" (u64 1))

def systemCreateAccountSpec : ProofForge.Contract.ContractSpec :=
  build "SolanaSystemCreateAccountCpi" do
    scalarState "nonce" .u64
    scalarState "lamports" .u64
    scalarState "space" .u64

    systemCreateAccount
      "create_state"
      "payer"
      "new_state"
      "lamports"
      "space"
      "program"

    entrySelector "create" "02" do
      invokeSystemCreateAccount
        "create_state"
        "payer"
        "new_state"
        "lamports"
        "space"
        "program"
      effect (storageScalarWrite "nonce" (u64 1))

def tokenParamAmountSpec : ProofForge.Contract.ContractSpec :=
  build "SolanaTokenParamCpi" do
    scalarState "nonce" .u64

    splTokenTransferChecked
      "token_transfer"
      "source"
      "mint"
      "destination"
      "authority"
      "amount"
      9

    entrySelectorWithParams "transfer" "03" #[("amount", .u64)] .unit do
      invokeSplTokenTransferChecked
        "token_transfer"
        "source"
        "mint"
        "destination"
        "authority"
        "amount"
        9
      effect (storageScalarWrite "nonce" (localVar "amount"))

def main : IO UInt32 := do
  match ProofForge.Backend.Solana.Package.renderPackageForSpec "system-cpi" systemTransferSpec with
  | .ok pkg =>
      let some asmFile := pkg.files.find? (fun file => file.path == pkg.asmPath)
        | throw <| IO.userError "package missing sBPF assembly"
      let asm := asmFile.contents
      let some manifestFile := pkg.files.find? (fun file => file.path == "manifest.toml")
        | throw <| IO.userError "package missing manifest.toml"
      let manifest := manifestFile.contents
      require (contains manifest "{ name = \"nonce\", index = 0, signer = false, writable = true, owner = \"program\" },")
        "manifest missing state account schema"
      require (contains manifest "{ name = \"payer\", index = 1, signer = true, writable = true, owner = \"any\" },")
        "manifest missing payer account schema"
      require (contains manifest "{ name = \"recipient\", index = 2, signer = false, writable = true, owner = \"any\" },")
        "manifest missing recipient account schema"
      require (contains manifest "{ name = \"system_program\", index = 3, signer = false, writable = false, owner = \"executable\" }")
        "manifest missing system program account schema"
      require (contains asm "account.validation[1:payer]: signer=true")
        "assembly missing payer signer validation"
      require (contains asm "account.validation[1:payer]: writable=true")
        "assembly missing payer writable validation"
      require (contains asm "account.validation[2:recipient]: writable=true")
        "assembly missing recipient writable validation"
      require (contains asm "sol_cpi_lamport_transfer:")
        "assembly missing System CPI helper label"
      require (contains asm "solana.cpi.pack system.transfer")
        "assembly missing system.transfer packing marker"
      require (contains asm "solana.cpi.program_id system_program")
        "assembly missing system program id packing marker"
      require (contains asm "solana.cpi.account_meta payer key_ptr account[1]")
        "assembly missing payer account meta packing"
      require (contains asm "solana.cpi.account_info payer account[1]")
        "assembly missing payer account info binding"
      require (contains asm "solana.cpi.account_info recipient account[2]")
        "assembly missing recipient account info packing"
      require (!contains asm "solana.cpi.account_info recipient placeholder")
        "recipient account info should use input account layout, not placeholder"
      require (contains asm "solana.cpi.data system.transfer: u32 discriminator=2, u64 lamports")
        "assembly missing system transfer data packing marker"
      require (contains asm "solana.cpi.value lamports from state lamports")
        "assembly missing system transfer lamports state binding"
      require (contains asm "stxw [r8+0], r3")
        "assembly missing system transfer discriminator store"
      require (contains asm "stxdw [r8+4], r3")
        "assembly missing system transfer lamports store"
      require (contains asm "solana.cpi.instruction record: C SolInstruction")
        "assembly missing C SolInstruction record marker"
      require (contains asm "stxdw [r5+0], r8")
        "assembly missing instruction program_id ptr store"
      require (contains asm "stxdw [r5+8], r7")
        "assembly missing instruction accounts ptr store"
      require (contains asm "stxdw [r5+24], r8")
        "assembly missing instruction data ptr store"
      require (contains asm "solana.cpi.signer_seeds none")
        "assembly missing no signer seed marker"
      require (contains asm "r1=instruction_ptr r2=account_infos_ptr r3=num_accounts r4=signer_seeds_ptr r5=num_signers")
        "assembly missing CPI syscall register contract"
      require (contains asm "call sol_invoke_signed_c")
        "assembly missing sol_invoke_signed_c syscall"
  | .error err =>
      throw <| IO.userError s!"Solana CPI packing render failed: {err.render}"

  match ProofForge.Backend.Solana.Package.renderPackageForSpec
      "memo-cpi" ProofForge.Solana.Examples.MemoCpi.spec with
  | .ok pkg =>
      let some asmFile := pkg.files.find? (fun file => file.path == pkg.asmPath)
        | throw <| IO.userError "memo-cpi package missing sBPF assembly"
      let some manifestFile := pkg.files.find? (fun file => file.path == "manifest.toml")
        | throw <| IO.userError "memo-cpi package missing manifest.toml"
      let asm := asmFile.contents
      let manifest := manifestFile.contents
      require (contains manifest "name = \"log_memo\"")
        "memo manifest missing log_memo instruction"
      require (contains manifest "min_data_len = 9")
        "memo manifest missing memoArg instruction-data length"
      require (contains manifest "{ name = \"memoArg\", type = \"U64\", offset = 1, byte_size = 8, encoding = \"le-u64\" }")
        "memo manifest missing memoArg parameter schema"
      require (contains manifest "{ name = \"last_memo_word\", index = 0, signer = false, writable = true, owner = \"program\" },")
        "memo manifest missing state account schema"
      require (contains manifest "{ name = \"memo\", index = 1, signer = false, writable = false, owner = \"executable\" }")
        "memo manifest missing Memo program account schema"
      require (contains manifest "program = \"memo\"")
        "memo manifest missing Memo CPI program"
      require (contains manifest "protocol = \"memo\"")
        "memo manifest missing Memo CPI protocol"
      require (contains manifest "data_layout = \"memo.memo\"")
        "memo manifest missing Memo CPI data layout"
      require (contains manifest "memo_source = \"memoArg\"")
        "memo manifest missing memo source metadata"
      require (contains asm "account.validation[1:memo]: owner=executable")
        "memo assembly missing executable Memo program validation"
      require (contains asm "sol_cpi_memo_call:")
        "memo assembly missing Memo CPI helper label"
      require (contains asm "solana.cpi.data memo.memo: raw bytes (len=8) from instruction param memoArg")
        "memo assembly missing raw memo data packing marker"
      require (contains asm "solana.cpi.program_id memo")
        "memo assembly missing Memo program id packing marker"
      require (contains asm "mov64 r3, 8")
        "memo assembly missing memo data length"
      require (contains asm "call sol_invoke_signed_c")
        "memo assembly missing sol_invoke_signed_c syscall"
  | .error err =>
      throw <| IO.userError s!"Solana Memo CPI packing render failed: {err.render}"

  match ProofForge.Backend.Solana.Package.renderPackageForSpec "system-create-cpi" systemCreateAccountSpec with
  | .ok pkg =>
      let some asmFile := pkg.files.find? (fun file => file.path == pkg.asmPath)
        | throw <| IO.userError "create-account package missing sBPF assembly"
      let asm := asmFile.contents
      require (contains asm "sol_cpi_create_state:")
        "assembly missing System create_account CPI helper label"
      require (contains asm "solana.cpi.data system.create_account: u32 discriminator=0, u64 lamports, u64 space, pubkey owner")
        "assembly missing system.create_account data packing marker"
      require (contains asm "solana.cpi.value lamports from state lamports")
        "assembly missing create_account lamports state binding"
      require (contains asm "solana.cpi.value space from state space")
        "assembly missing create_account space state binding"
      require (contains asm "solana.cpi.value owner=current_program_id")
        "assembly missing create_account owner program id binding"
      require (contains asm "mov64 r3, 52")
        "assembly missing system.create_account data length"
  | .error err =>
      throw <| IO.userError s!"Solana create-account CPI packing render failed: {err.render}"

  match ProofForge.Backend.Solana.Package.renderPackageForSpec "token-param-cpi" tokenParamAmountSpec with
  | .ok pkg =>
      let some asmFile := pkg.files.find? (fun file => file.path == pkg.asmPath)
        | throw <| IO.userError "token-param package missing sBPF assembly"
      let some manifestFile := pkg.files.find? (fun file => file.path == "manifest.toml")
        | throw <| IO.userError "token-param package missing manifest.toml"
      let asm := asmFile.contents
      let manifest := manifestFile.contents
      require (contains manifest "min_data_len = 9")
        "manifest missing transfer minimum instruction-data length"
      require (contains manifest "{ name = \"amount\", type = \"U64\", offset = 1, byte_size = 8, encoding = \"le-u64\" }")
        "manifest missing transfer amount parameter schema"
      require (contains asm "instruction_data.length >= 9")
        "assembly missing transfer parameter payload length check"
      require (contains asm "entrypoint.param[transfer.amount]: U64 @ instruction_data+1")
        "assembly missing transfer amount parameter decoding"
      require (contains asm "stxdw [r10-8], r2")
        "assembly missing parameter local stack store"
      require (contains asm "solana.cpi.data spl-token.transfer_checked: u8 instruction=12, u64 amount, u8 decimals=9")
        "assembly missing transfer_checked data packing marker"
      require (contains asm "solana.cpi.value amount from instruction param amount")
        "assembly missing transfer_checked amount instruction parameter binding"
      require (!contains asm "solana.cpi.value amount source=amount placeholder=0")
        "transfer_checked amount should not fall back to placeholder"
      require (contains asm "stb [r8+0], 12")
        "assembly missing transfer_checked instruction tag store"
      require (contains asm "stb [r8+9], 9")
        "assembly missing transfer_checked decimals store"
  | .error err =>
      throw <| IO.userError s!"Solana token-param CPI packing render failed: {err.render}"

  match ProofForge.Backend.Solana.Package.renderPackageForSpec
      "token-ops-cpi" ProofForge.Solana.Examples.SplTokenOpsCpi.spec with
  | .ok pkg =>
      let some asmFile := pkg.files.find? (fun file => file.path == pkg.asmPath)
        | throw <| IO.userError "token-ops package missing sBPF assembly"
      let some manifestFile := pkg.files.find? (fun file => file.path == "manifest.toml")
        | throw <| IO.userError "token-ops package missing manifest.toml"
      let asm := asmFile.contents
      let manifest := manifestFile.contents
      require (contains manifest "name = \"mint\"")
        "token ops manifest missing mint entrypoint"
      require (contains manifest "name = \"burn\"")
        "token ops manifest missing burn entrypoint"
      require (contains manifest "name = \"approve\"")
        "token ops manifest missing approve entrypoint"
      require (contains manifest "name = \"revoke\"")
        "token ops manifest missing revoke entrypoint"
      require (contains manifest "{ name = \"last_mint_amount\", index = 0, signer = false, writable = true, owner = \"program\" },")
        "token ops manifest missing state account schema"
      require (contains manifest "{ name = \"mint\", index = 1, signer = false, writable = true, owner = \"any\" },")
        "token ops manifest missing mint account schema"
      require (contains manifest "{ name = \"destination\", index = 2, signer = false, writable = true, owner = \"any\" },")
        "token ops manifest missing destination account schema"
      require (contains manifest "{ name = \"authority\", index = 3, signer = true, writable = false, owner = \"any\" },")
        "token ops manifest missing authority account schema"
      require (contains manifest "{ name = \"spl_token\", index = 4, signer = false, writable = false, owner = \"executable\" },")
        "token ops manifest missing SPL Token account schema"
      require (contains manifest "{ name = \"source\", index = 5, signer = false, writable = true, owner = \"any\" },")
        "token ops manifest missing source account schema"
      require (contains manifest "{ name = \"delegate\", index = 6, signer = false, writable = false, owner = \"any\" }")
        "token ops manifest missing delegate account schema"
      require (contains asm "sol_cpi_token_mint:")
        "assembly missing SPL Token mint_to helper label"
      require (contains asm "sol_cpi_token_burn:")
        "assembly missing SPL Token burn helper label"
      require (contains asm "sol_cpi_token_approve:")
        "assembly missing SPL Token approve helper label"
      require (contains asm "sol_cpi_token_revoke:")
        "assembly missing SPL Token revoke helper label"
      require (contains asm "solana.cpi.data spl-token.mint_to: u8 instruction=7, u64 amount")
        "assembly missing SPL Token mint_to data packing"
      require (contains asm "solana.cpi.data spl-token.burn: u8 instruction=8, u64 amount")
        "assembly missing SPL Token burn data packing"
      require (contains asm "solana.cpi.data spl-token.approve: u8 instruction=4, u64 amount")
        "assembly missing SPL Token approve data packing"
      require (contains asm "solana.cpi.data spl-token.revoke: u8 instruction=5")
        "assembly missing SPL Token revoke data packing"
      require (contains asm "mov64 r3, 9")
        "assembly missing amount-based SPL Token data length"
      require (contains asm "mov64 r3, 1")
        "assembly missing revoke SPL Token data length"
      require (contains asm "solana.cpi.value amount from instruction param amount")
        "assembly missing SPL Token ops amount instruction parameter binding"
      require (contains asm "stb [r8+0], 7")
        "assembly missing mint_to instruction tag store"
      require (contains asm "stb [r8+0], 8")
        "assembly missing burn instruction tag store"
      require (contains asm "stb [r8+0], 4")
        "assembly missing approve instruction tag store"
      require (contains asm "stb [r8+0], 5")
        "assembly missing revoke instruction tag store"
      require (contains asm "call sol_cpi_token_mint")
        "assembly missing mint entrypoint CPI helper call"
      require (contains asm "call sol_cpi_token_burn")
        "assembly missing burn entrypoint CPI helper call"
      require (contains asm "call sol_cpi_token_approve")
        "assembly missing approve entrypoint CPI helper call"
      require (contains asm "call sol_cpi_token_revoke")
        "assembly missing revoke entrypoint CPI helper call"
  | .error err =>
      throw <| IO.userError s!"Solana token-ops CPI packing render failed: {err.render}"

  match ProofForge.Backend.Solana.Package.renderPackageForSpec
      "token-close-cpi" ProofForge.Solana.Examples.SplTokenCloseAccountCpi.spec with
  | .ok pkg =>
      let some asmFile := pkg.files.find? (fun file => file.path == pkg.asmPath)
        | throw <| IO.userError "token-close package missing sBPF assembly"
      let some manifestFile := pkg.files.find? (fun file => file.path == "manifest.toml")
        | throw <| IO.userError "token-close package missing manifest.toml"
      let asm := asmFile.contents
      let manifest := manifestFile.contents
      require (contains manifest "name = \"close_account\"")
        "token close manifest missing close_account entrypoint"
      require (contains manifest "{ name = \"last_close_marker\", index = 0, signer = false, writable = true, owner = \"program\" },")
        "token close manifest missing state account schema"
      require (contains manifest "{ name = \"token_account\", index = 1, signer = false, writable = true, owner = \"any\" },")
        "token close manifest missing token account schema"
      require (contains manifest "{ name = \"destination\", index = 2, signer = false, writable = true, owner = \"any\" },")
        "token close manifest missing destination account schema"
      require (contains manifest "{ name = \"authority\", index = 3, signer = true, writable = false, owner = \"any\" },")
        "token close manifest missing authority account schema"
      require (contains manifest "{ name = \"spl_token\", index = 4, signer = false, writable = false, owner = \"executable\" }")
        "token close manifest missing SPL Token account schema"
      require (contains manifest "instruction = \"close_account\"")
        "token close manifest missing close_account CPI"
      require (contains manifest "data_layout = \"spl-token.close_account\"")
        "token close manifest missing close_account data layout"
      require (contains asm "sol_cpi_token_close:")
        "assembly missing SPL Token close_account helper label"
      require (contains asm "solana.cpi.data spl-token.close_account: u8 instruction=9")
        "assembly missing SPL Token close_account data packing"
      require (contains asm "mov64 r3, 1")
        "assembly missing close_account SPL Token data length"
      require (contains asm "stb [r8+0], 9")
        "assembly missing close_account instruction tag store"
      require (contains asm "call sol_cpi_token_close")
        "assembly missing close_account entrypoint CPI helper call"
  | .error err =>
      throw <| IO.userError s!"Solana token-close CPI packing render failed: {err.render}"

  match ProofForge.Backend.Solana.Package.renderPackageForSpec
      "token-authority-cpi" ProofForge.Solana.Examples.SplTokenAuthorityCpi.spec with
  | .ok pkg =>
      let some asmFile := pkg.files.find? (fun file => file.path == pkg.asmPath)
        | throw <| IO.userError "token-authority package missing sBPF assembly"
      let some manifestFile := pkg.files.find? (fun file => file.path == "manifest.toml")
        | throw <| IO.userError "token-authority package missing manifest.toml"
      let asm := asmFile.contents
      let manifest := manifestFile.contents
      require (contains manifest "name = \"set_authority\"")
        "token authority manifest missing set_authority entrypoint"
      require (contains manifest "{ name = \"last_authority_marker\", index = 0, signer = false, writable = true, owner = \"program\" },")
        "token authority manifest missing state account schema"
      require (contains manifest "{ name = \"mint\", index = 1, signer = false, writable = true, owner = \"any\" },")
        "token authority manifest missing mint account schema"
      require (contains manifest "{ name = \"authority\", index = 2, signer = true, writable = false, owner = \"any\" },")
        "token authority manifest missing authority account schema"
      require (contains manifest "{ name = \"spl_token\", index = 3, signer = false, writable = false, owner = \"executable\" },")
        "token authority manifest missing SPL Token program account schema"
      require (contains manifest "{ name = \"new_authority\", index = 4, signer = false, writable = false, owner = \"any\" }")
        "token authority manifest missing new authority account schema"
      require (contains manifest "instruction = \"set_authority\"")
        "token authority manifest missing set_authority CPI"
      require (contains manifest "data_layout = \"spl-token.set_authority\"")
        "token authority manifest missing set_authority data layout"
      require (contains manifest "authority_type = \"mint_tokens\"")
        "token authority manifest missing authority_type metadata"
      require (contains manifest "new_authority = \"new_authority\"")
        "token authority manifest missing new_authority metadata"
      require (contains asm "sol_cpi_token_set_authority:")
        "assembly missing SPL Token set_authority helper label"
      require (contains asm "solana.cpi.data spl-token.set_authority: u8 instruction=6, u8 authority_type=mint_tokens, option=some, pubkey new_authority")
        "assembly missing SPL Token set_authority data packing"
      require (contains asm "solana.cpi.value new_authority from account new_authority")
        "assembly missing new_authority account-key data binding"
      require (contains asm "mov64 r3, 35")
        "assembly missing set_authority SPL Token data length"
      require (contains asm "stb [r8+0], 6")
        "assembly missing set_authority instruction tag store"
      require (contains asm "stb [r8+1], 0")
        "assembly missing set_authority MintTokens authority type store"
      require (contains asm "stb [r8+2], 1")
        "assembly missing set_authority new-authority option store"
      require (contains asm "call sol_cpi_token_set_authority")
        "assembly missing set_authority entrypoint CPI helper call"
  | .error err =>
      throw <| IO.userError s!"Solana token-authority CPI packing render failed: {err.render}"

  match ProofForge.Backend.Solana.Package.renderPackageForSpec
      "token-2022-cpi" ProofForge.Solana.Examples.SplToken2022Cpi.spec with
  | .ok pkg =>
      let some asmFile := pkg.files.find? (fun file => file.path == pkg.asmPath)
        | throw <| IO.userError "token-2022 package missing sBPF assembly"
      let some manifestFile := pkg.files.find? (fun file => file.path == "manifest.toml")
        | throw <| IO.userError "token-2022 package missing manifest.toml"
      let some idlFile := pkg.files.find? (fun file => file.path == pkg.idlPath)
        | throw <| IO.userError "token-2022 package missing proof-forge-idl.json"
      let asm := asmFile.contents
      let manifest := manifestFile.contents
      let idl := idlFile.contents
      require (contains manifest "program = \"spl_token_2022\"")
        "Token-2022 manifest missing program id"
      require (contains manifest "protocol = \"token-2022\"")
        "Token-2022 manifest missing protocol metadata"
      require (contains manifest "data_layout = \"token-2022.initialize_transfer_fee_config\"")
        "Token-2022 manifest missing transfer-fee config layout"
      require (contains manifest "transfer_fee_config_authority = \"transfer_fee_config_authority\"")
        "Token-2022 manifest missing transfer-fee config authority source"
      require (contains manifest "withdraw_withheld_authority = \"withdraw_withheld_authority\"")
        "Token-2022 manifest missing withdraw-withheld authority source"
      require (contains manifest "transfer_fee_basis_points = \"basis_points\"")
        "Token-2022 manifest missing transfer-fee bps source"
      require (contains manifest "maximum_fee = \"maximum_fee\"")
        "Token-2022 manifest missing maximum fee source"
      require (contains manifest "data_layout = \"token-2022.transfer_checked_with_fee\"")
        "Token-2022 manifest missing transfer_checked_with_fee layout"
      require (contains manifest "fee_source = \"fee\"")
        "Token-2022 manifest missing fee source"
      require (contains manifest "data_layout = \"token-2022.initialize_non_transferable_mint\"")
        "Token-2022 manifest missing non-transferable layout"
      require (contains manifest "data_layout = \"token-2022.initialize_metadata_pointer\"")
        "Token-2022 manifest missing metadata-pointer layout"
      require (contains manifest "metadata_pointer_authority = \"metadata_pointer_authority\"")
        "Token-2022 manifest missing metadata-pointer authority source"
      require (contains manifest "metadata_address = \"metadata_address\"")
        "Token-2022 manifest missing metadata address source"
      require (contains manifest "data_layout = \"token-2022.initialize_default_account_state\"")
        "Token-2022 manifest missing default-account-state layout"
      require (contains manifest "default_account_state = \"2\"")
        "Token-2022 manifest missing default-account-state metadata"
      require (contains manifest "data_layout = \"token-2022.initialize_immutable_owner\"")
        "Token-2022 manifest missing immutable-owner layout"
      require (contains manifest "data_layout = \"token-2022.initialize_permanent_delegate\"")
        "Token-2022 manifest missing permanent-delegate layout"
      require (contains manifest "permanent_delegate = \"permanent_delegate\"")
        "Token-2022 manifest missing permanent-delegate metadata"
      require (contains manifest "data_layout = \"token-2022.initialize_interest_bearing_mint\"")
        "Token-2022 manifest missing interest-bearing layout"
      require (contains manifest "interest_rate_authority = \"interest_rate_authority\"")
        "Token-2022 manifest missing interest-rate authority metadata"
      require (contains manifest "interest_rate = \"250\"")
        "Token-2022 manifest missing interest rate metadata"
      require (contains manifest "data_layout = \"token-2022.enable_required_memo_transfers\"")
        "Token-2022 manifest missing memo-transfer layout"
      require (contains manifest "memo_transfer_required = \"true\"")
        "Token-2022 manifest missing memo-transfer metadata"
      require (contains manifest "data_layout = \"token-2022.initialize_transfer_hook\"")
        "Token-2022 manifest missing transfer-hook layout"
      require (contains manifest "transfer_hook_authority = \"transfer_hook_authority\"")
        "Token-2022 manifest missing transfer-hook authority metadata"
      require (contains manifest "transfer_hook_program = \"transfer_hook_program\"")
        "Token-2022 manifest missing transfer-hook program metadata"
      require (contains manifest "num_token_accounts = \"1\"")
        "Token-2022 manifest missing withheld source count"
      require (contains idl "\"feeSource\": \"fee\"")
        "Token-2022 IDL missing feeSource"
      require (contains idl "\"transferFeeConfigAuthority\": \"transfer_fee_config_authority\"")
        "Token-2022 IDL missing transferFeeConfigAuthority"
      require (contains idl "\"withdrawWithheldAuthority\": \"withdraw_withheld_authority\"")
        "Token-2022 IDL missing withdrawWithheldAuthority"
      require (contains idl "\"numTokenAccounts\": \"1\"")
        "Token-2022 IDL missing numTokenAccounts"
      require (contains idl "\"metadataPointerAuthority\": \"metadata_pointer_authority\"")
        "Token-2022 IDL missing metadataPointerAuthority"
      require (contains idl "\"metadataAddress\": \"metadata_address\"")
        "Token-2022 IDL missing metadataAddress"
      require (contains idl "\"defaultAccountState\": \"2\"")
        "Token-2022 IDL missing defaultAccountState"
      require (contains idl "\"permanentDelegate\": \"permanent_delegate\"")
        "Token-2022 IDL missing permanentDelegate"
      require (contains idl "\"interestRateAuthority\": \"interest_rate_authority\"")
        "Token-2022 IDL missing interestRateAuthority"
      require (contains idl "\"interestRate\": \"250\"")
        "Token-2022 IDL missing interestRate"
      require (contains idl "\"memoTransferRequired\": \"true\"")
        "Token-2022 IDL missing memoTransferRequired"
      require (contains idl "\"transferHookAuthority\": \"transfer_hook_authority\"")
        "Token-2022 IDL missing transferHookAuthority"
      require (contains idl "\"transferHookProgram\": \"transfer_hook_program\"")
        "Token-2022 IDL missing transferHookProgram"
      require (contains asm "sol_cpi_token_2022_init_fee_config:")
        "assembly missing Token-2022 init fee config helper label"
      require (contains asm "sol_cpi_token_2022_transfer_with_fee:")
        "assembly missing Token-2022 transfer-with-fee helper label"
      require (contains asm "sol_cpi_token_2022_init_non_transferable:")
        "assembly missing Token-2022 non-transferable helper label"
      require (contains asm "sol_cpi_token_2022_init_metadata_pointer:")
        "assembly missing Token-2022 metadata-pointer helper label"
      require (contains asm "sol_cpi_token_2022_init_default_account_state:")
        "assembly missing Token-2022 default-account-state helper label"
      require (contains asm "sol_cpi_token_2022_init_immutable_owner:")
        "assembly missing Token-2022 immutable-owner helper label"
      require (contains asm "sol_cpi_token_2022_init_permanent_delegate:")
        "assembly missing Token-2022 permanent-delegate helper label"
      require (contains asm "sol_cpi_token_2022_init_interest_bearing:")
        "assembly missing Token-2022 interest-bearing helper label"
      require (contains asm "sol_cpi_token_2022_enable_memo_transfer:")
        "assembly missing Token-2022 memo-transfer helper label"
      require (contains asm "sol_cpi_token_2022_init_transfer_hook:")
        "assembly missing Token-2022 transfer-hook helper label"
      require (contains asm "solana.cpi.program_id spl_token_2022 TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb")
        "assembly missing Token-2022 program id packing marker"
      require (contains asm "solana.cpi.data token-2022.initialize_transfer_fee_config: u8 instruction=26, u8 transfer_fee_instruction=0")
        "assembly missing transfer-fee config data packing marker"
      require (contains asm "solana.cpi.value transfer_fee_config_authority from account transfer_fee_config_authority")
        "assembly missing transfer-fee config authority pubkey binding"
      require (contains asm "solana.cpi.value withdraw_withheld_authority from account withdraw_withheld_authority")
        "assembly missing withdraw-withheld authority pubkey binding"
      require (contains asm "solana.cpi.value transfer_fee_basis_points from instruction param basis_points")
        "assembly missing transfer-fee bps parameter binding"
      require (contains asm "solana.cpi.value maximum_fee from instruction param maximum_fee")
        "assembly missing maximum-fee parameter binding"
      require (contains asm "solana.cpi.data token-2022.transfer_checked_with_fee: u8 instruction=26, u8 transfer_fee_instruction=1, u64 amount, u8 decimals=9, u64 fee")
        "assembly missing transfer_checked_with_fee data packing marker"
      require (contains asm "solana.cpi.value fee from instruction param fee")
        "assembly missing transfer fee parameter binding"
      require (contains asm "solana.cpi.data token-2022.withdraw_withheld_tokens_from_mint: u8 instruction=26, u8 transfer_fee_instruction=2")
        "assembly missing withdraw-withheld-from-mint data packing marker"
      require (contains asm "solana.cpi.data token-2022.withdraw_withheld_tokens_from_accounts: u8 instruction=26, u8 transfer_fee_instruction=3, u8 num_token_accounts=1")
        "assembly missing withdraw-withheld-from-accounts data packing marker"
      require (contains asm "solana.cpi.data token-2022.harvest_withheld_tokens_to_mint: u8 instruction=26, u8 transfer_fee_instruction=4")
        "assembly missing harvest-withheld-to-mint data packing marker"
      require (contains asm "solana.cpi.data token-2022.set_transfer_fee: u8 instruction=26, u8 transfer_fee_instruction=5, u16 transfer_fee_basis_points, u64 maximum_fee")
        "assembly missing set-transfer-fee data packing marker"
      require (contains asm "solana.cpi.data token-2022.initialize_non_transferable_mint: u8 instruction=32")
        "assembly missing initialize_non_transferable_mint data packing marker"
      require (contains asm "solana.cpi.data token-2022.initialize_metadata_pointer: u8 instruction=39, u8 metadata_pointer_instruction=0, pubkey authority, pubkey metadata_address")
        "assembly missing initialize_metadata_pointer data packing marker"
      require (contains asm "solana.cpi.value metadata_pointer_authority from account metadata_pointer_authority")
        "assembly missing metadata-pointer authority pubkey binding"
      require (contains asm "solana.cpi.value metadata_address from account metadata_address")
        "assembly missing metadata address pubkey binding"
      require (contains asm "solana.cpi.data token-2022.initialize_default_account_state: u8 instruction=28, u8 default_account_state_instruction=0, u8 state=2")
        "assembly missing initialize_default_account_state data packing marker"
      require (contains asm "solana.cpi.data token-2022.initialize_immutable_owner: u8 instruction=22")
        "assembly missing initialize_immutable_owner data packing marker"
      require (contains asm "solana.cpi.data token-2022.initialize_permanent_delegate: u8 instruction=35, pubkey delegate")
        "assembly missing initialize_permanent_delegate data packing marker"
      require (contains asm "solana.cpi.value permanent_delegate from account permanent_delegate")
        "assembly missing permanent delegate pubkey binding"
      require (contains asm "solana.cpi.data token-2022.initialize_interest_bearing_mint: u8 instruction=33, u8 interest_bearing_mint_instruction=0, pubkey rate_authority, i16 rate=250")
        "assembly missing initialize_interest_bearing_mint data packing marker"
      require (contains asm "solana.cpi.value interest_rate_authority from account interest_rate_authority")
        "assembly missing interest-rate authority pubkey binding"
      require (contains asm "solana.cpi.data token-2022.enable_required_memo_transfers: u8 instruction=30, u8 memo_transfer_instruction=0")
        "assembly missing enable_required_memo_transfers data packing marker"
      require (contains asm "solana.cpi.data token-2022.initialize_transfer_hook: u8 instruction=36, u8 transfer_hook_instruction=0, pubkey authority, pubkey transfer_hook_program_id")
        "assembly missing initialize_transfer_hook data packing marker"
      require (contains asm "solana.cpi.value transfer_hook_authority from account transfer_hook_authority")
        "assembly missing transfer-hook authority pubkey binding"
      require (contains asm "solana.cpi.value transfer_hook_program from account transfer_hook_program")
        "assembly missing transfer-hook program pubkey binding"
      require (contains asm "mov64 r3, 78")
        "assembly missing initialize_transfer_fee_config data length"
      require (contains asm "mov64 r3, 19")
        "assembly missing transfer_checked_with_fee data length"
      require (contains asm "mov64 r3, 12")
        "assembly missing set_transfer_fee data length"
      require (contains asm "mov64 r3, 66")
        "assembly missing 66-byte Token-2022 pubkey-extension data length"
      require (contains asm "mov64 r3, 3")
        "assembly missing initialize_default_account_state data length"
      require (contains asm "mov64 r3, 33")
        "assembly missing initialize_permanent_delegate data length"
      require (contains asm "mov64 r3, 36")
        "assembly missing initialize_interest_bearing_mint data length"
      require (contains asm "mov64 r3, 2")
        "assembly missing memo-transfer data length"
      require (contains asm "stb [r8+0], 26")
        "assembly missing Token-2022 extension top-level tag store"
      require (contains asm "stb [r8+1], 1")
        "assembly missing transfer_checked_with_fee sub-instruction store"
      require (contains asm "stb [r8+10], 9")
        "assembly missing transfer_checked_with_fee decimals store"
      require (contains asm "stxdw [r8+11], r3")
        "assembly missing transfer_checked_with_fee fee store"
      require (contains asm "stxh [r8+68], r3")
        "assembly missing transfer-fee config bps store"
      require (contains asm "stxh [r8+2], r3")
        "assembly missing set_transfer_fee bps store"
      require (contains asm "stb [r8+0], 32")
        "assembly missing non-transferable instruction tag store"
      require (contains asm "stb [r8+0], 39")
        "assembly missing metadata-pointer instruction tag store"
      require (contains asm "stb [r8+1], 0")
        "assembly missing metadata/default extension initialize sub-instruction store"
      require (contains asm "stxdw [r8+34], r3")
        "assembly missing metadata address pubkey data store"
      require (contains asm "stb [r8+0], 28")
        "assembly missing default-account-state instruction tag store"
      require (contains asm "stb [r8+2], 2")
        "assembly missing default-account-state frozen state store"
      require (contains asm "stb [r8+0], 22")
        "assembly missing immutable-owner instruction tag store"
      require (contains asm "stb [r8+0], 35")
        "assembly missing permanent-delegate instruction tag store"
      require (contains asm "stb [r8+0], 33")
        "assembly missing interest-bearing instruction tag store"
      require (contains asm "mov64 r3, 250")
        "assembly missing interest-bearing rate immediate load"
      require (contains asm "stxh [r8+34], r3")
        "assembly missing interest-bearing rate store"
      require (contains asm "stb [r8+0], 30")
        "assembly missing memo-transfer instruction tag store"
      require (contains asm "stb [r8+0], 36")
        "assembly missing transfer-hook instruction tag store"
      require (contains asm "call sol_cpi_token_2022_transfer_with_fee")
        "assembly missing transfer_with_fee entrypoint CPI helper call"
      require (contains asm "call sol_cpi_token_2022_init_non_transferable")
        "assembly missing non-transferable entrypoint CPI helper call"
      require (contains asm "call sol_cpi_token_2022_init_metadata_pointer")
        "assembly missing metadata-pointer entrypoint CPI helper call"
      require (contains asm "call sol_cpi_token_2022_init_default_account_state")
        "assembly missing default-account-state entrypoint CPI helper call"
      require (contains asm "call sol_cpi_token_2022_init_immutable_owner")
        "assembly missing immutable-owner entrypoint CPI helper call"
      require (contains asm "call sol_cpi_token_2022_init_permanent_delegate")
        "assembly missing permanent-delegate entrypoint CPI helper call"
      require (contains asm "call sol_cpi_token_2022_init_interest_bearing")
        "assembly missing interest-bearing entrypoint CPI helper call"
      require (contains asm "call sol_cpi_token_2022_enable_memo_transfer")
        "assembly missing memo-transfer entrypoint CPI helper call"
      require (contains asm "call sol_cpi_token_2022_init_transfer_hook")
        "assembly missing transfer-hook entrypoint CPI helper call"
  | .error err =>
      throw <| IO.userError s!"Solana Token-2022 CPI packing render failed: {err.render}"

  match ProofForge.Backend.Solana.Package.renderPackageForSpec
      "token-2022-pausable-cpi" ProofForge.Solana.Examples.SplToken2022PausableCpi.spec with
  | .ok pkg =>
      let some asmFile := pkg.files.find? (fun file => file.path == pkg.asmPath)
        | throw <| IO.userError "token-2022 pausable package missing sBPF assembly"
      let some manifestFile := pkg.files.find? (fun file => file.path == "manifest.toml")
        | throw <| IO.userError "token-2022 pausable package missing manifest.toml"
      let some idlFile := pkg.files.find? (fun file => file.path == pkg.idlPath)
        | throw <| IO.userError "token-2022 pausable package missing proof-forge-idl.json"
      let asm := asmFile.contents
      let manifest := manifestFile.contents
      let idl := idlFile.contents
      require (contains manifest "data_layout = \"token-2022.initialize_pausable_config\"")
        "Token-2022 pausable manifest missing pausable-config layout"
      require (contains manifest "pausable_authority = \"pausable_authority\"")
        "Token-2022 pausable manifest missing pausable authority metadata"
      require (contains manifest "data_layout = \"token-2022.pause\"")
        "Token-2022 pausable manifest missing pause layout"
      require (contains manifest "data_layout = \"token-2022.resume\"")
        "Token-2022 pausable manifest missing resume layout"
      require (contains idl "\"pausableAuthority\": \"pausable_authority\"")
        "Token-2022 pausable IDL missing pausableAuthority"
      require (contains asm "sol_cpi_token_2022_init_pausable_config:")
        "assembly missing Token-2022 pausable-config helper label"
      require (contains asm "sol_cpi_token_2022_pause:")
        "assembly missing Token-2022 pause helper label"
      require (contains asm "sol_cpi_token_2022_resume:")
        "assembly missing Token-2022 resume helper label"
      require (contains asm "solana.cpi.data token-2022.initialize_pausable_config: u8 instruction=44, u8 pausable_instruction=0, pubkey authority")
        "assembly missing initialize_pausable_config data packing marker"
      require (contains asm "solana.cpi.value pausable_authority from account pausable_authority")
        "assembly missing pausable authority pubkey binding"
      require (contains asm "solana.cpi.data token-2022.pause: u8 instruction=44, u8 pausable_instruction=1")
        "assembly missing pause data packing marker"
      require (contains asm "solana.cpi.data token-2022.resume: u8 instruction=44, u8 pausable_instruction=2")
        "assembly missing resume data packing marker"
      require (contains asm "mov64 r3, 34")
        "assembly missing initialize_pausable_config data length"
      require (contains asm "mov64 r3, 2")
        "assembly missing pause/resume data length"
      require (contains asm "stb [r8+0], 44")
        "assembly missing pausable instruction tag store"
      require (contains asm "stb [r8+1], 2")
        "assembly missing pausable resume sub-instruction store"
      require (contains asm "call sol_cpi_token_2022_init_pausable_config")
        "assembly missing pausable-config entrypoint CPI helper call"
      require (contains asm "call sol_cpi_token_2022_pause")
        "assembly missing pause entrypoint CPI helper call"
      require (contains asm "call sol_cpi_token_2022_resume")
        "assembly missing resume entrypoint CPI helper call"
  | .error err =>
      throw <| IO.userError s!"Solana Token-2022 Pausable CPI packing render failed: {err.render}"

  match ProofForge.Backend.Solana.Package.renderPackageForSpec
      "token-2022-transfer-hook" ProofForge.Solana.Examples.SplToken2022TransferHook.spec with
  | .ok pkg =>
      let some asmFile := pkg.files.find? (fun file => file.path == pkg.asmPath)
        | throw <| IO.userError "token-2022 transfer-hook package missing sBPF assembly"
      let some manifestFile := pkg.files.find? (fun file => file.path == "manifest.toml")
        | throw <| IO.userError "token-2022 transfer-hook package missing manifest.toml"
      let some idlFile := pkg.files.find? (fun file => file.path == pkg.idlPath)
        | throw <| IO.userError "token-2022 transfer-hook package missing proof-forge-idl.json"
      let asm := asmFile.contents
      let manifest := manifestFile.contents
      let idl := idlFile.contents
      require (contains manifest "name = \"initialize_extra_account_meta_list\"")
        "Token-2022 transfer-hook manifest missing init entrypoint"
      require (contains manifest "name = \"execute\"")
        "Token-2022 transfer-hook manifest missing execute entrypoint"
      require (contains manifest "names = [\"source\", \"mint\", \"destination\", \"authority\", \"extra_account_meta_list\", \"sentinel\", \"system_program\"]")
        "Token-2022 transfer-hook manifest missing account order"
      require (contains manifest "{ name = \"source\", index = 0, signer = true, writable = true, owner = \"any\" },")
        "Token-2022 transfer-hook init manifest missing payer signer/writable source"
      require (contains manifest "{ name = \"source\", index = 0, signer = false, writable = false, owner = \"any\" },")
        "Token-2022 transfer-hook execute manifest should not require source signer/writable"
      require (contains manifest "{ name = \"extra_account_meta_list\", index = 4, signer = false, writable = true, owner = \"any\" },")
        "Token-2022 transfer-hook init manifest missing writable validation account"
      require (contains manifest "{ name = \"extra_account_meta_list\", index = 4, signer = false, writable = false, owner = \"any\" },")
        "Token-2022 transfer-hook execute manifest should not require writable validation account"
      require (contains manifest "{ name = \"amount\", type = \"U64\", offset = 8, byte_size = 8, encoding = \"le-u64\" }")
        "Token-2022 transfer-hook manifest missing execute amount offset"
      require (contains manifest "{ name = \"rent_lamports\", type = \"U64\", offset = 1, byte_size = 8, encoding = \"le-u64\" },")
        "Token-2022 transfer-hook manifest missing rent_lamports offset"
      require (contains manifest "{ name = \"extra_meta_space\", type = \"U64\", offset = 9, byte_size = 8, encoding = \"le-u64\" },")
        "Token-2022 transfer-hook manifest missing extra_meta_space offset"
      require (contains manifest "{ name = \"extra_meta_bump\", type = \"U64\", offset = 17, byte_size = 8, encoding = \"le-u64\" }")
        "Token-2022 transfer-hook manifest missing extra_meta_bump offset"
      require (contains manifest "signer_seeds = [\"utf8:extra-account-metas\", \"account:mint\", \"bump:extra_meta_bump\"]")
        "Token-2022 transfer-hook manifest missing PDA signer seeds"
      require (contains manifest "[[solana.entrypoint_transfer_hook_extra_meta]]")
        "Token-2022 transfer-hook manifest missing extra-meta action"
      require (contains manifest "extra_accounts = [\"sentinel\", \"system_program\"]")
        "Token-2022 transfer-hook manifest missing routed extra accounts"
      require (contains manifest "execute_discriminator = \"692565c54bfb661a\"")
        "Token-2022 transfer-hook manifest missing execute discriminator"
      require (contains manifest "extra_account_count = 2")
        "Token-2022 transfer-hook manifest missing routed account count"
      require (contains idl "\"extraAccounts\": [\"sentinel\", \"system_program\"]")
        "Token-2022 transfer-hook IDL missing routed extra accounts"
      require (contains idl "\"extraAccountCount\": 2")
        "Token-2022 transfer-hook IDL missing routed account count"
      require (contains asm "external discriminator dispatch execute: 8 bytes")
        "assembly missing transfer-hook external discriminator dispatch"
      require (contains asm "entrypoint.param[execute.amount]: U64 @ instruction_data+8")
        "assembly missing transfer-hook execute amount decode offset"
      require (contains asm "sol_execute:\n\n  ; account.validation: generated account schema\n  ; account.validation[6:system_program]: owner=executable")
        "assembly execute validation should only require routed executable account"
      require (contains asm "solana.cpi.signer_seed create_extra_account_meta_list[0] \"extra-account-metas\"")
        "assembly missing transfer-hook literal signer seed"
      require (contains asm "solana.cpi.signer_seed create_extra_account_meta_list[1] account mint pubkey")
        "assembly missing transfer-hook account signer seed"
      require (contains asm "solana.cpi.signer_seed create_extra_account_meta_list[2] bump extra_meta_bump from instruction param")
        "assembly missing transfer-hook bump signer seed"
      require (contains asm "sub64 r7, 2352\n  stxdw [r7+0], r8\n  mov64 r3, 32\n  stxdw [r7+8], r3")
        "assembly should place second signer seed table entry at the next higher stack address"
      require (contains asm "sub64 r7, 2336\n  stxdw [r7+0], r8\n  mov64 r3, 1\n  stxdw [r7+8], r3")
        "assembly should place third signer seed table entry at the next higher stack address"
      require (contains asm "call sol_transfer_hook_extra_meta_write_extra_account_meta_list")
        "assembly missing transfer-hook extra-meta helper call"
      require (contains asm "solana.transfer_hook.extra_account_meta_list: TLV ExecuteInstruction, static account metas=2")
        "assembly missing transfer-hook TLV marker"
      require (contains asm "stw [r8+8], 74")
        "assembly missing transfer-hook TLV payload length"
      require (contains asm "stw [r8+12], 2")
        "assembly missing transfer-hook extra account count store"
      require (contains asm "stb [r8+16], 0")
        "assembly missing transfer-hook first static meta discriminator"
      require (contains asm "stb [r8+51], 0")
        "assembly missing transfer-hook second static meta discriminator"
      require (contains asm "stb [r8+84], 0")
        "assembly missing transfer-hook second static meta signer byte"
      require (contains asm "stb [r8+85], 0")
        "assembly missing transfer-hook second static meta writable byte"
  | .error err =>
      throw <| IO.userError s!"Solana Token-2022 transfer-hook packing render failed: {err.render}"

  match ProofForge.Backend.Solana.Package.renderPackageForSpec
      "associated-token-cpi" ProofForge.Solana.Examples.AssociatedTokenCpi.spec with
  | .ok pkg =>
      let some asmFile := pkg.files.find? (fun file => file.path == pkg.asmPath)
        | throw <| IO.userError "associated-token package missing sBPF assembly"
      let some manifestFile := pkg.files.find? (fun file => file.path == "manifest.toml")
        | throw <| IO.userError "associated-token package missing manifest.toml"
      let asm := asmFile.contents
      let manifest := manifestFile.contents
      require (contains manifest "name = \"create_associated\"")
        "associated-token manifest missing create_associated entrypoint"
      require (contains manifest "{ name = \"last_created_marker\", index = 0, signer = false, writable = true, owner = \"program\" },")
        "associated-token manifest missing state account schema"
      require (contains manifest "{ name = \"payer\", index = 1, signer = true, writable = true, owner = \"any\" },")
        "associated-token manifest missing payer account schema"
      require (contains manifest "{ name = \"associated_account\", index = 2, signer = false, writable = true, owner = \"any\" },")
        "associated-token manifest missing associated account schema"
      require (contains manifest "{ name = \"wallet\", index = 3, signer = false, writable = false, owner = \"any\" },")
        "associated-token manifest missing wallet account schema"
      require (contains manifest "{ name = \"mint\", index = 4, signer = false, writable = false, owner = \"any\" },")
        "associated-token manifest missing mint account schema"
      require (contains manifest "{ name = \"system_program\", index = 5, signer = false, writable = false, owner = \"executable\" },")
        "associated-token manifest missing system program account schema"
      require (contains manifest "{ name = \"spl_token\", index = 6, signer = false, writable = false, owner = \"executable\" },")
        "associated-token manifest missing SPL Token program account schema"
      require (contains manifest "{ name = \"associated_token\", index = 7, signer = false, writable = false, owner = \"executable\" }")
        "associated-token manifest missing associated token program account schema"
      require (contains manifest "program = \"associated_token\"")
        "associated-token manifest missing associated token program"
      require (contains manifest "instruction = \"create_idempotent\"")
        "associated-token manifest missing create_idempotent CPI"
      require (contains manifest "protocol = \"associated-token\"")
        "associated-token manifest missing protocol metadata"
      require (contains manifest "token_program = \"spl_token\"")
        "associated-token manifest missing token program metadata"
      require (contains manifest "data_layout = \"associated-token.create_idempotent\"")
        "associated-token manifest missing create_idempotent data layout"
      require (contains asm "sol_cpi_create_associated_token:")
        "assembly missing Associated Token helper label"
      require (contains asm "sub64 r7, 256")
        "assembly missing separated CPI account-meta frame for 6-account Associated Token CPI"
      require (contains asm "solana.cpi.data associated-token.create_idempotent: u8 instruction=1")
        "assembly missing Associated Token create_idempotent data packing"
      require (contains asm "solana.cpi.account_info associated_account account[2]")
        "assembly missing associated account info binding"
      require (contains asm "mov64 r3, 6\n  stxdw [r5+16], r3")
        "assembly missing associated token instruction account count"
      require (contains asm "mov64 r3, 1")
        "assembly missing associated token data length"
      require (contains asm "stb [r8+0], 1")
        "assembly missing create_idempotent instruction tag store"
      require (contains asm "call sol_cpi_create_associated_token")
        "assembly missing create_associated entrypoint CPI helper call"
  | .error err =>
      throw <| IO.userError s!"Solana associated-token CPI packing render failed: {err.render}"

  IO.println "solana-cpi-packing: ok"
  return 0

end ProofForge.Tests.SolanaCpiPacking

def main : IO UInt32 :=
  ProofForge.Tests.SolanaCpiPacking.main
