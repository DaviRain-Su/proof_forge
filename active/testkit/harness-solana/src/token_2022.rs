use std::str::FromStr;

use anyhow::{anyhow, ensure, Context, Result};
use solana_address::Address;
use solana_instruction::{AccountMeta, Instruction};
use solana_keypair::Keypair;
use solana_signer::Signer;
use spl_tlv_account_resolution::state::ExtraAccountMetaList;
use spl_token_2022_interface::{
    extension::{
        default_account_state::DefaultAccountState,
        immutable_owner::ImmutableOwner,
        interest_bearing_mint::InterestBearingConfig,
        memo_transfer::MemoTransfer,
        metadata_pointer::MetadataPointer,
        non_transferable::{NonTransferable, NonTransferableAccount},
        pausable::PausableConfig,
        permanent_delegate::PermanentDelegate,
        transfer_fee::{
            instruction as transfer_fee_instruction, TransferFeeAmount, TransferFeeConfig,
        },
        transfer_hook::{instruction as transfer_hook_instruction, TransferHook},
        BaseStateWithExtensions, ExtensionType, StateWithExtensions,
    },
    instruction as token_instruction,
    state::{Account as Token2022AccountState, AccountState, Mint as Token2022MintState},
};
use spl_transfer_hook_interface::instruction as transfer_hook_interface_instruction;
use spl_type_length_value::state::TlvStateBorrowed;

use crate::{
    live_rpc::LiveRpc,
    spl_token::{
        create_empty_associated_token_account_for_program, parse_mint_account, parse_token_account,
        MintAccount, TokenAccount,
    },
};

pub const TOKEN_2022_PROGRAM_ID: &str = "TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb";
const TRANSFER_HOOK_EXTRA_ACCOUNT_METAS_SEED: &[u8] = b"extra-account-metas";

#[derive(Debug, Clone)]
pub struct TransferHookExtraAccountMeta {
    pub discriminator: u8,
    pub address: Address,
    pub is_signer: bool,
    pub is_writable: bool,
}

pub fn token_2022_program_id() -> Address {
    Address::from_str(TOKEN_2022_PROGRAM_ID).expect("Token-2022 program id is valid")
}

pub fn create_non_transferable_mint(
    rpc: &LiveRpc,
    payer: &Keypair,
    decimals: u8,
    mint_authority: Address,
) -> Result<Keypair> {
    let token_program = token_2022_program_id();
    let mint = Keypair::new();
    let space = ExtensionType::try_calculate_account_len::<Token2022MintState>(&[
        ExtensionType::NonTransferable,
    ])
    .map_err(|err| anyhow!("failed to calculate Token-2022 mint length: {err:?}"))?;
    let lamports = rpc.minimum_balance_for_rent_exemption(space as u64)?;
    let create = solana_system_interface::instruction::create_account(
        &payer.pubkey(),
        &mint.pubkey(),
        lamports,
        space as u64,
        &token_program,
    );
    let initialize_non_transferable =
        token_instruction::initialize_non_transferable_mint(&token_program, &mint.pubkey())
            .map_err(|err| anyhow!("failed to build non-transferable init instruction: {err:?}"))?;
    let initialize_mint = token_instruction::initialize_mint(
        &token_program,
        &mint.pubkey(),
        &mint_authority,
        None,
        decimals,
    )
    .map_err(|err| anyhow!("failed to build Token-2022 initialize_mint instruction: {err:?}"))?;
    rpc.send_and_confirm(
        &[create, initialize_non_transferable, initialize_mint],
        &[payer, &mint],
    )
    .context("failed to create and initialize Token-2022 non-transferable mint")?;
    Ok(mint)
}

pub fn create_transfer_fee_mint(
    rpc: &LiveRpc,
    payer: &Keypair,
    decimals: u8,
    mint_authority: Address,
    transfer_fee_config_authority: Address,
    withdraw_withheld_authority: Address,
    transfer_fee_basis_points: u16,
    maximum_fee: u64,
) -> Result<Keypair> {
    let token_program = token_2022_program_id();
    let mint = Keypair::new();
    let space = ExtensionType::try_calculate_account_len::<Token2022MintState>(&[
        ExtensionType::TransferFeeConfig,
    ])
    .map_err(|err| anyhow!("failed to calculate Token-2022 mint length: {err:?}"))?;
    let lamports = rpc.minimum_balance_for_rent_exemption(space as u64)?;
    let create = solana_system_interface::instruction::create_account(
        &payer.pubkey(),
        &mint.pubkey(),
        lamports,
        space as u64,
        &token_program,
    );
    let initialize_transfer_fee_config = transfer_fee_instruction::initialize_transfer_fee_config(
        &token_program,
        &mint.pubkey(),
        Some(&transfer_fee_config_authority),
        Some(&withdraw_withheld_authority),
        transfer_fee_basis_points,
        maximum_fee,
    )
    .map_err(|err| anyhow!("failed to build transfer-fee config init instruction: {err:?}"))?;
    let initialize_mint = token_instruction::initialize_mint(
        &token_program,
        &mint.pubkey(),
        &mint_authority,
        None,
        decimals,
    )
    .map_err(|err| anyhow!("failed to build Token-2022 initialize_mint instruction: {err:?}"))?;
    rpc.send_and_confirm(
        &[create, initialize_transfer_fee_config, initialize_mint],
        &[payer, &mint],
    )
    .context("failed to create and initialize Token-2022 transfer-fee mint")?;
    Ok(mint)
}

pub fn create_pausable_mint_account(rpc: &LiveRpc, payer: &Keypair) -> Result<Keypair> {
    let token_program = token_2022_program_id();
    let mint = Keypair::new();
    let space =
        ExtensionType::try_calculate_account_len::<Token2022MintState>(&[ExtensionType::Pausable])
            .map_err(|err| {
                anyhow!("failed to calculate Token-2022 pausable mint length: {err:?}")
            })?;
    let lamports = rpc.minimum_balance_for_rent_exemption(space as u64)?;
    let create = solana_system_interface::instruction::create_account(
        &payer.pubkey(),
        &mint.pubkey(),
        lamports,
        space as u64,
        &token_program,
    );
    rpc.send_and_confirm(&[create], &[payer, &mint])
        .context("failed to create Token-2022 pausable mint account")?;
    Ok(mint)
}

pub fn create_transfer_hook_mint_account(rpc: &LiveRpc, payer: &Keypair) -> Result<Keypair> {
    let token_program = token_2022_program_id();
    let mint = Keypair::new();
    let space = ExtensionType::try_calculate_account_len::<Token2022MintState>(&[
        ExtensionType::TransferHook,
    ])
    .map_err(|err| anyhow!("failed to calculate Token-2022 transfer-hook mint length: {err:?}"))?;
    let lamports = rpc.minimum_balance_for_rent_exemption(space as u64)?;
    let create = solana_system_interface::instruction::create_account(
        &payer.pubkey(),
        &mint.pubkey(),
        lamports,
        space as u64,
        &token_program,
    );
    rpc.send_and_confirm(&[create], &[payer, &mint])
        .context("failed to create Token-2022 transfer-hook mint account")?;
    Ok(mint)
}

pub fn create_mint_account_with_extensions(
    rpc: &LiveRpc,
    payer: &Keypair,
    extensions: &[ExtensionType],
    label: &str,
) -> Result<Keypair> {
    let token_program = token_2022_program_id();
    let mint = Keypair::new();
    let space = ExtensionType::try_calculate_account_len::<Token2022MintState>(extensions)
        .map_err(|err| anyhow!("failed to calculate Token-2022 {label} mint length: {err:?}"))?;
    let lamports = rpc.minimum_balance_for_rent_exemption(space as u64)?;
    let create = solana_system_interface::instruction::create_account(
        &payer.pubkey(),
        &mint.pubkey(),
        lamports,
        space as u64,
        &token_program,
    );
    rpc.send_and_confirm(&[create], &[payer, &mint])
        .with_context(|| format!("failed to create Token-2022 {label} mint account"))?;
    Ok(mint)
}

pub fn create_token_account_with_extensions(
    rpc: &LiveRpc,
    payer: &Keypair,
    extensions: &[ExtensionType],
    label: &str,
) -> Result<Keypair> {
    let token_program = token_2022_program_id();
    let account = Keypair::new();
    let space = ExtensionType::try_calculate_account_len::<Token2022AccountState>(extensions)
        .map_err(|err| anyhow!("failed to calculate Token-2022 {label} account length: {err:?}"))?;
    let lamports = rpc.minimum_balance_for_rent_exemption(space as u64)?;
    let create = solana_system_interface::instruction::create_account(
        &payer.pubkey(),
        &account.pubkey(),
        lamports,
        space as u64,
        &token_program,
    );
    rpc.send_and_confirm(&[create], &[payer, &account])
        .with_context(|| format!("failed to create Token-2022 {label} token account"))?;
    Ok(account)
}

pub fn create_empty_associated_token_account(
    rpc: &LiveRpc,
    payer: &Keypair,
    wallet: Address,
    mint: Address,
) -> Result<Address> {
    create_empty_associated_token_account_for_program(
        rpc,
        payer,
        wallet,
        mint,
        token_2022_program_id(),
    )
}

pub fn mint_to(
    rpc: &LiveRpc,
    payer: &Keypair,
    mint: Address,
    destination: Address,
    authority: &Keypair,
    amount: u64,
) -> Result<String> {
    let token_program = token_2022_program_id();
    let instruction = token_instruction::mint_to(
        &token_program,
        &mint,
        &destination,
        &authority.pubkey(),
        &[],
        amount,
    )
    .map_err(|err| anyhow!("failed to build Token-2022 mint_to instruction: {err:?}"))?;
    send_authority_instruction(rpc, payer, authority, instruction)
        .context("failed to mint Token-2022 amount")
}

pub fn initialize_mint(
    rpc: &LiveRpc,
    payer: &Keypair,
    mint: Address,
    decimals: u8,
    mint_authority: Address,
) -> Result<String> {
    initialize_mint_with_freeze_authority(rpc, payer, mint, decimals, mint_authority, None)
}

pub fn initialize_mint_with_freeze_authority(
    rpc: &LiveRpc,
    payer: &Keypair,
    mint: Address,
    decimals: u8,
    mint_authority: Address,
    freeze_authority: Option<Address>,
) -> Result<String> {
    let token_program = token_2022_program_id();
    let instruction = token_instruction::initialize_mint(
        &token_program,
        &mint,
        &mint_authority,
        freeze_authority.as_ref(),
        decimals,
    )
    .map_err(|err| anyhow!("failed to build Token-2022 initialize_mint instruction: {err:?}"))?;
    rpc.send_and_confirm(&[instruction], &[payer])
        .context("failed to initialize Token-2022 mint")
}

pub fn initialize_account(
    rpc: &LiveRpc,
    payer: &Keypair,
    account: Address,
    mint: Address,
    owner: Address,
) -> Result<String> {
    let token_program = token_2022_program_id();
    let instruction =
        token_instruction::initialize_account(&token_program, &account, &mint, &owner).map_err(
            |err| anyhow!("failed to build Token-2022 initialize_account instruction: {err:?}"),
        )?;
    rpc.send_and_confirm(&[instruction], &[payer])
        .context("failed to initialize Token-2022 account")
}

pub fn initialize_transfer_hook_mint(
    rpc: &LiveRpc,
    payer: &Keypair,
    mint: Address,
    decimals: u8,
    mint_authority: Address,
    transfer_hook_authority: Address,
    transfer_hook_program_id: Address,
) -> Result<String> {
    let token_program = token_2022_program_id();
    let initialize_hook = transfer_hook_instruction::initialize(
        &token_program,
        &mint,
        Some(transfer_hook_authority),
        Some(transfer_hook_program_id),
    )
    .map_err(|err| anyhow!("failed to build Token-2022 transfer-hook init instruction: {err:?}"))?;
    let initialize_mint =
        token_instruction::initialize_mint(&token_program, &mint, &mint_authority, None, decimals)
            .map_err(|err| {
                anyhow!("failed to build Token-2022 initialize_mint instruction: {err:?}")
            })?;
    rpc.send_and_confirm(&[initialize_hook, initialize_mint], &[payer])
        .context("failed to initialize Token-2022 transfer-hook mint")
}

pub fn transfer_checked(
    rpc: &LiveRpc,
    payer: &Keypair,
    source: Address,
    mint: Address,
    destination: Address,
    authority: &Keypair,
    amount: u64,
    decimals: u8,
) -> Result<String> {
    let instruction = transfer_checked_instruction(
        source,
        mint,
        destination,
        authority.pubkey(),
        amount,
        decimals,
    )?;
    send_authority_instruction(rpc, payer, authority, instruction)
        .context("failed to transfer checked Token-2022 amount")
}

#[allow(clippy::too_many_arguments)]
pub fn transfer_checked_with_fee(
    rpc: &LiveRpc,
    payer: &Keypair,
    source: Address,
    mint: Address,
    destination: Address,
    authority: &Keypair,
    amount: u64,
    decimals: u8,
    fee: u64,
) -> Result<String> {
    let token_program = token_2022_program_id();
    let instruction = transfer_fee_instruction::transfer_checked_with_fee(
        &token_program,
        &source,
        &mint,
        &destination,
        &authority.pubkey(),
        &[],
        amount,
        decimals,
        fee,
    )
    .map_err(|err| anyhow!("failed to build transfer_checked_with_fee instruction: {err:?}"))?;
    send_authority_instruction(rpc, payer, authority, instruction)
        .context("failed to transfer checked Token-2022 amount with fee")
}

pub fn withdraw_withheld_tokens_from_accounts(
    rpc: &LiveRpc,
    payer: &Keypair,
    mint: Address,
    destination: Address,
    authority: &Keypair,
    sources: &[Address],
) -> Result<String> {
    let token_program = token_2022_program_id();
    let source_refs: Vec<&Address> = sources.iter().collect();
    let instruction = transfer_fee_instruction::withdraw_withheld_tokens_from_accounts(
        &token_program,
        &mint,
        &destination,
        &authority.pubkey(),
        &[],
        &source_refs,
    )
    .map_err(|err| {
        anyhow!("failed to build withdraw_withheld_tokens_from_accounts instruction: {err:?}")
    })?;
    send_authority_instruction(rpc, payer, authority, instruction)
        .context("failed to withdraw Token-2022 withheld fees from accounts")
}

pub fn harvest_withheld_tokens_to_mint(
    rpc: &LiveRpc,
    payer: &Keypair,
    mint: Address,
    sources: &[Address],
) -> Result<String> {
    let token_program = token_2022_program_id();
    let source_refs: Vec<&Address> = sources.iter().collect();
    let instruction = transfer_fee_instruction::harvest_withheld_tokens_to_mint(
        &token_program,
        &mint,
        &source_refs,
    )
    .map_err(|err| {
        anyhow!("failed to build harvest_withheld_tokens_to_mint instruction: {err:?}")
    })?;
    rpc.send_and_confirm(&[instruction], &[payer])
        .context("failed to harvest Token-2022 withheld fees to mint")
}

pub fn withdraw_withheld_tokens_from_mint(
    rpc: &LiveRpc,
    payer: &Keypair,
    mint: Address,
    destination: Address,
    authority: &Keypair,
) -> Result<String> {
    let token_program = token_2022_program_id();
    let instruction = transfer_fee_instruction::withdraw_withheld_tokens_from_mint(
        &token_program,
        &mint,
        &destination,
        &authority.pubkey(),
        &[],
    )
    .map_err(|err| {
        anyhow!("failed to build withdraw_withheld_tokens_from_mint instruction: {err:?}")
    })?;
    send_authority_instruction(rpc, payer, authority, instruction)
        .context("failed to withdraw Token-2022 withheld fees from mint")
}

pub fn burn(
    rpc: &LiveRpc,
    payer: &Keypair,
    account: Address,
    mint: Address,
    owner: &Keypair,
    amount: u64,
) -> Result<String> {
    let token_program = token_2022_program_id();
    let instruction = token_instruction::burn(
        &token_program,
        &account,
        &mint,
        &owner.pubkey(),
        &[],
        amount,
    )
    .map_err(|err| anyhow!("failed to build Token-2022 burn instruction: {err:?}"))?;
    send_authority_instruction(rpc, payer, owner, instruction)
        .context("failed to burn Token-2022 amount")
}

pub fn expect_transfer_checked_failure(
    rpc: &LiveRpc,
    payer: &Keypair,
    source: Address,
    mint: Address,
    destination: Address,
    authority: &Keypair,
    amount: u64,
    decimals: u8,
) -> Result<crate::live_rpc::ExpectedTransactionFailure> {
    let instruction = transfer_checked_instruction(
        source,
        mint,
        destination,
        authority.pubkey(),
        amount,
        decimals,
    )?;
    if payer.pubkey() == authority.pubkey() {
        rpc.send_and_confirm_expect_failure(&[instruction], &[payer])
    } else {
        rpc.send_and_confirm_expect_failure(&[instruction], &[payer, authority])
    }
}

#[allow(clippy::too_many_arguments)]
pub fn transfer_checked_with_hook(
    rpc: &LiveRpc,
    payer: &Keypair,
    source: Address,
    mint: Address,
    destination: Address,
    authority: &Keypair,
    transfer_hook_program_id: Address,
    amount: u64,
    decimals: u8,
) -> Result<String> {
    let instruction = transfer_checked_with_hook_instruction(
        rpc,
        source,
        mint,
        destination,
        authority.pubkey(),
        transfer_hook_program_id,
        amount,
        decimals,
    )?;
    send_authority_instruction(rpc, payer, authority, instruction)
        .context("failed to transfer checked Token-2022 amount with transfer hook")
}

#[allow(clippy::too_many_arguments)]
pub fn expect_transfer_checked_with_hook_failure(
    rpc: &LiveRpc,
    payer: &Keypair,
    source: Address,
    mint: Address,
    destination: Address,
    authority: &Keypair,
    transfer_hook_program_id: Address,
    amount: u64,
    decimals: u8,
) -> Result<crate::live_rpc::ExpectedTransactionFailure> {
    let instruction = transfer_checked_with_hook_instruction(
        rpc,
        source,
        mint,
        destination,
        authority.pubkey(),
        transfer_hook_program_id,
        amount,
        decimals,
    )?;
    if payer.pubkey() == authority.pubkey() {
        rpc.send_and_confirm_expect_failure(&[instruction], &[payer])
    } else {
        rpc.send_and_confirm_expect_failure(&[instruction], &[payer, authority])
    }
}

pub fn parse_account(data: &[u8]) -> Result<TokenAccount> {
    parse_token_account(data)
}

pub fn parse_mint(data: &[u8]) -> Result<MintAccount> {
    parse_mint_account(data)
}

pub fn assert_non_transferable_mint(data: &[u8]) -> Result<()> {
    let state = StateWithExtensions::<Token2022MintState>::unpack(data)
        .map_err(|err| anyhow!("failed to parse Token-2022 mint extensions: {err:?}"))?;
    state
        .get_extension::<NonTransferable>()
        .map_err(|err| anyhow!("mint missing NonTransferable extension: {err:?}"))?;
    Ok(())
}

pub fn assert_transfer_fee_config(
    data: &[u8],
    transfer_fee_config_authority: Address,
    withdraw_withheld_authority: Address,
    transfer_fee_basis_points: u16,
    maximum_fee: u64,
) -> Result<()> {
    let config = transfer_fee_config(data)?;
    ensure!(
        config.transfer_fee_config_authority.0.to_bytes()
            == transfer_fee_config_authority.to_bytes(),
        "transfer-fee config authority mismatch: expected {}, got {}",
        transfer_fee_config_authority,
        config.transfer_fee_config_authority.0
    );
    ensure!(
        config.withdraw_withheld_authority.0.to_bytes() == withdraw_withheld_authority.to_bytes(),
        "withdraw-withheld authority mismatch: expected {}, got {}",
        withdraw_withheld_authority,
        config.withdraw_withheld_authority.0
    );
    ensure!(
        u16::from(config.newer_transfer_fee.transfer_fee_basis_points) == transfer_fee_basis_points,
        "transfer-fee basis points mismatch: expected {transfer_fee_basis_points}, got {}",
        u16::from(config.newer_transfer_fee.transfer_fee_basis_points)
    );
    ensure!(
        u64::from(config.newer_transfer_fee.maximum_fee) == maximum_fee,
        "transfer-fee maximum mismatch: expected {maximum_fee}, got {}",
        u64::from(config.newer_transfer_fee.maximum_fee)
    );
    Ok(())
}

pub fn assert_pausable_config(data: &[u8], authority: Address, paused: bool) -> Result<()> {
    let config = pausable_config(data)?;
    ensure!(
        config.authority.0.to_bytes() == authority.to_bytes(),
        "pausable authority mismatch: expected {authority}, got {}",
        config.authority.0
    );
    let actual_paused = bool::from(config.paused);
    ensure!(
        actual_paused == paused,
        "pausable paused state mismatch: expected {paused}, got {actual_paused}"
    );
    Ok(())
}

pub fn assert_transfer_hook_config(
    data: &[u8],
    authority: Address,
    transfer_hook_program_id: Address,
) -> Result<()> {
    let config = transfer_hook_config(data)?;
    ensure!(
        config.authority.0.to_bytes() == authority.to_bytes(),
        "transfer-hook authority mismatch: expected {authority}, got {}",
        config.authority.0
    );
    ensure!(
        config.program_id.0.to_bytes() == transfer_hook_program_id.to_bytes(),
        "transfer-hook program id mismatch: expected {transfer_hook_program_id}, got {}",
        config.program_id.0
    );
    Ok(())
}

pub fn assert_metadata_pointer_config(
    data: &[u8],
    authority: Address,
    metadata_address: Address,
) -> Result<()> {
    let config = metadata_pointer_config(data)?;
    ensure!(
        config.authority.0.to_bytes() == authority.to_bytes(),
        "metadata-pointer authority mismatch: expected {authority}, got {}",
        config.authority.0
    );
    ensure!(
        config.metadata_address.0.to_bytes() == metadata_address.to_bytes(),
        "metadata-pointer address mismatch: expected {metadata_address}, got {}",
        config.metadata_address.0
    );
    Ok(())
}

pub fn assert_default_account_state(data: &[u8], expected: AccountState) -> Result<()> {
    let config = default_account_state_config(data)?;
    let actual = config.state;
    let expected_u8 = u8::from(expected);
    ensure!(
        actual == expected_u8,
        "default account state mismatch: expected {expected_u8}, got {actual}"
    );
    Ok(())
}

pub fn assert_immutable_owner_account(data: &[u8]) -> Result<()> {
    let state = StateWithExtensions::<Token2022AccountState>::unpack(data)
        .map_err(|err| anyhow!("failed to parse Token-2022 account extensions: {err:?}"))?;
    state
        .get_extension::<ImmutableOwner>()
        .map_err(|err| anyhow!("account missing ImmutableOwner extension: {err:?}"))?;
    Ok(())
}

pub fn assert_permanent_delegate(data: &[u8], delegate: Address) -> Result<()> {
    let config = permanent_delegate_config(data)?;
    ensure!(
        config.delegate.0.to_bytes() == delegate.to_bytes(),
        "permanent delegate mismatch: expected {delegate}, got {}",
        config.delegate.0
    );
    Ok(())
}

pub fn assert_interest_bearing_config(
    data: &[u8],
    rate_authority: Address,
    current_rate: i16,
) -> Result<()> {
    let config = interest_bearing_config(data)?;
    ensure!(
        config.rate_authority.0.to_bytes() == rate_authority.to_bytes(),
        "interest-bearing rate authority mismatch: expected {rate_authority}, got {}",
        config.rate_authority.0
    );
    let actual_rate = i16::from(config.current_rate);
    ensure!(
        actual_rate == current_rate,
        "interest-bearing current rate mismatch: expected {current_rate}, got {actual_rate}"
    );
    Ok(())
}

pub fn assert_memo_transfer(data: &[u8], required: bool) -> Result<()> {
    let state = StateWithExtensions::<Token2022AccountState>::unpack(data)
        .map_err(|err| anyhow!("failed to parse Token-2022 account extensions: {err:?}"))?;
    let config = state
        .get_extension::<MemoTransfer>()
        .map_err(|err| anyhow!("account missing MemoTransfer extension: {err:?}"))?;
    let actual = bool::from(config.require_incoming_transfer_memos);
    ensure!(
        actual == required,
        "memo-transfer required flag mismatch: expected {required}, got {actual}"
    );
    Ok(())
}

pub fn transfer_hook_extra_account_meta_address(
    mint: Address,
    program_id: Address,
) -> (Address, u8) {
    Address::find_program_address(
        &[TRANSFER_HOOK_EXTRA_ACCOUNT_METAS_SEED, mint.as_ref()],
        &program_id,
    )
}

pub fn transfer_hook_extra_account_meta_space(count: usize) -> Result<usize> {
    ExtraAccountMetaList::size_of(count).map_err(|err| {
        anyhow!("failed to calculate transfer-hook extra-account-meta size: {err:?}")
    })
}

pub fn transfer_hook_extra_account_metas(data: &[u8]) -> Result<Vec<TransferHookExtraAccountMeta>> {
    let tlv_state = TlvStateBorrowed::unpack(data)
        .map_err(|err| anyhow!("failed to parse transfer-hook extra-account-meta TLV: {err:?}"))?;
    let metas = ExtraAccountMetaList::unpack_with_tlv_state::<
        transfer_hook_interface_instruction::ExecuteInstruction,
    >(&tlv_state)
    .map_err(|err| anyhow!("failed to parse transfer-hook execute extra-account metas: {err:?}"))?;
    metas
        .iter()
        .map(|meta| {
            Ok(TransferHookExtraAccountMeta {
                discriminator: meta.discriminator,
                address: Address::from(meta.address_config),
                is_signer: bool::from(meta.is_signer),
                is_writable: bool::from(meta.is_writable),
            })
        })
        .collect()
}

pub fn calculate_epoch_fee(data: &[u8], epoch: u64, amount: u64) -> Result<u64> {
    transfer_fee_config(data)?
        .calculate_epoch_fee(epoch, amount)
        .context("failed to calculate Token-2022 transfer fee")
}

pub fn account_withheld_amount(data: &[u8], label: &str) -> Result<u64> {
    let state = StateWithExtensions::<Token2022AccountState>::unpack(data)
        .map_err(|err| anyhow!("failed to parse Token-2022 {label} account extensions: {err:?}"))?;
    let amount = state
        .get_extension::<TransferFeeAmount>()
        .map_err(|err| anyhow!("{label} account missing TransferFeeAmount extension: {err:?}"))?;
    Ok(u64::from(amount.withheld_amount))
}

pub fn mint_withheld_amount(data: &[u8]) -> Result<u64> {
    Ok(u64::from(transfer_fee_config(data)?.withheld_amount))
}

pub fn assert_non_transferable_account(data: &[u8], label: &str) -> Result<()> {
    let state = StateWithExtensions::<Token2022AccountState>::unpack(data)
        .map_err(|err| anyhow!("failed to parse Token-2022 {label} account extensions: {err:?}"))?;
    state
        .get_extension::<NonTransferableAccount>()
        .map_err(|err| {
            anyhow!("{label} account missing NonTransferableAccount extension: {err:?}")
        })?;
    state
        .get_extension::<ImmutableOwner>()
        .map_err(|err| anyhow!("{label} account missing ImmutableOwner extension: {err:?}"))?;
    Ok(())
}

pub fn verify_empty_account(data: &[u8], mint: Address, owner: Address, label: &str) -> Result<()> {
    let account = parse_account(data)?;
    ensure!(
        account.mint == mint,
        "{label} account mint mismatch: expected {mint}, got {}",
        account.mint
    );
    ensure!(
        account.owner == owner,
        "{label} account owner mismatch: expected {owner}, got {}",
        account.owner
    );
    ensure!(
        account.amount == 0,
        "{label} account should be empty, got {}",
        account.amount
    );
    assert_non_transferable_account(data, label)
}

fn transfer_fee_config(data: &[u8]) -> Result<TransferFeeConfig> {
    let state = StateWithExtensions::<Token2022MintState>::unpack(data)
        .map_err(|err| anyhow!("failed to parse Token-2022 mint extensions: {err:?}"))?;
    state
        .get_extension::<TransferFeeConfig>()
        .copied()
        .map_err(|err| anyhow!("mint missing TransferFeeConfig extension: {err:?}"))
}

fn pausable_config(data: &[u8]) -> Result<PausableConfig> {
    let state = StateWithExtensions::<Token2022MintState>::unpack(data)
        .map_err(|err| anyhow!("failed to parse Token-2022 mint extensions: {err:?}"))?;
    state
        .get_extension::<PausableConfig>()
        .copied()
        .map_err(|err| anyhow!("mint missing PausableConfig extension: {err:?}"))
}

fn transfer_hook_config(data: &[u8]) -> Result<TransferHook> {
    let state = StateWithExtensions::<Token2022MintState>::unpack(data)
        .map_err(|err| anyhow!("failed to parse Token-2022 mint extensions: {err:?}"))?;
    state
        .get_extension::<TransferHook>()
        .copied()
        .map_err(|err| anyhow!("mint missing TransferHook extension: {err:?}"))
}

fn metadata_pointer_config(data: &[u8]) -> Result<MetadataPointer> {
    let state = StateWithExtensions::<Token2022MintState>::unpack(data)
        .map_err(|err| anyhow!("failed to parse Token-2022 mint extensions: {err:?}"))?;
    state
        .get_extension::<MetadataPointer>()
        .copied()
        .map_err(|err| anyhow!("mint missing MetadataPointer extension: {err:?}"))
}

fn default_account_state_config(data: &[u8]) -> Result<DefaultAccountState> {
    let state = StateWithExtensions::<Token2022MintState>::unpack(data)
        .map_err(|err| anyhow!("failed to parse Token-2022 mint extensions: {err:?}"))?;
    state
        .get_extension::<DefaultAccountState>()
        .copied()
        .map_err(|err| anyhow!("mint missing DefaultAccountState extension: {err:?}"))
}

fn permanent_delegate_config(data: &[u8]) -> Result<PermanentDelegate> {
    let state = StateWithExtensions::<Token2022MintState>::unpack(data)
        .map_err(|err| anyhow!("failed to parse Token-2022 mint extensions: {err:?}"))?;
    state
        .get_extension::<PermanentDelegate>()
        .copied()
        .map_err(|err| anyhow!("mint missing PermanentDelegate extension: {err:?}"))
}

fn interest_bearing_config(data: &[u8]) -> Result<InterestBearingConfig> {
    let state = StateWithExtensions::<Token2022MintState>::unpack(data)
        .map_err(|err| anyhow!("failed to parse Token-2022 mint extensions: {err:?}"))?;
    state
        .get_extension::<InterestBearingConfig>()
        .copied()
        .map_err(|err| anyhow!("mint missing InterestBearingConfig extension: {err:?}"))
}

fn transfer_checked_instruction(
    source: Address,
    mint: Address,
    destination: Address,
    authority: Address,
    amount: u64,
    decimals: u8,
) -> Result<Instruction> {
    let token_program = token_2022_program_id();
    token_instruction::transfer_checked(
        &token_program,
        &source,
        &mint,
        &destination,
        &authority,
        &[],
        amount,
        decimals,
    )
    .map_err(|err| anyhow!("failed to build Token-2022 transfer_checked instruction: {err:?}"))
}

#[allow(clippy::too_many_arguments)]
pub fn transfer_checked_with_hook_instruction(
    rpc: &LiveRpc,
    source: Address,
    mint: Address,
    destination: Address,
    authority: Address,
    transfer_hook_program_id: Address,
    amount: u64,
    decimals: u8,
) -> Result<Instruction> {
    let mut instruction =
        transfer_checked_instruction(source, mint, destination, authority, amount, decimals)?;
    add_transfer_hook_extra_accounts(
        rpc,
        &mut instruction,
        source,
        mint,
        destination,
        authority,
        transfer_hook_program_id,
        amount,
    )?;
    Ok(instruction)
}

#[allow(clippy::too_many_arguments)]
fn add_transfer_hook_extra_accounts(
    rpc: &LiveRpc,
    instruction: &mut Instruction,
    source: Address,
    mint: Address,
    destination: Address,
    authority: Address,
    transfer_hook_program_id: Address,
    amount: u64,
) -> Result<()> {
    for required in [source, mint, destination, authority] {
        ensure!(
            instruction
                .accounts
                .iter()
                .any(|meta| meta.pubkey == required),
            "transfer-hook transfer instruction missing required account {required}"
        );
    }

    let validation_account =
        transfer_hook_extra_account_meta_address(mint, transfer_hook_program_id).0;
    let validation_data = rpc.account_data(validation_account).with_context(|| {
        format!("failed to read transfer-hook validation account {validation_account}")
    })?;
    let tlv_state = TlvStateBorrowed::unpack(&validation_data)
        .map_err(|err| anyhow!("failed to parse transfer-hook validation TLV: {err:?}"))?;
    let extra_metas = ExtraAccountMetaList::unpack_with_tlv_state::<
        transfer_hook_interface_instruction::ExecuteInstruction,
    >(&tlv_state)
    .map_err(|err| anyhow!("failed to parse transfer-hook execute extra-account metas: {err:?}"))?;

    let mut execute_instruction = transfer_hook_interface_instruction::execute(
        &transfer_hook_program_id,
        &source,
        &mint,
        &destination,
        &authority,
        amount,
    );
    execute_instruction
        .accounts
        .push(AccountMeta::new_readonly(validation_account, false));
    let mut account_key_datas = Vec::with_capacity(execute_instruction.accounts.len());
    for meta in &execute_instruction.accounts {
        let data = rpc
            .account_info_optional(meta.pubkey)
            .with_context(|| format!("failed to fetch account data for {}", meta.pubkey))?
            .map(|account| account.data);
        account_key_datas.push((meta.pubkey, data));
    }

    for extra_meta in extra_metas.iter() {
        let mut meta = extra_meta
            .resolve(
                &execute_instruction.data,
                &execute_instruction.program_id,
                |index| {
                    account_key_datas
                        .get(index)
                        .map(|(pubkey, data)| (pubkey, data.as_deref()))
                },
            )
            .map_err(|err| anyhow!("failed to resolve transfer-hook extra account: {err:?}"))?;
        de_escalate_account_meta(&mut meta, &execute_instruction.accounts);
        let data = rpc
            .account_info_optional(meta.pubkey)
            .with_context(|| format!("failed to fetch extra account data for {}", meta.pubkey))?
            .map(|account| account.data);
        account_key_datas.push((meta.pubkey, data));
        execute_instruction.accounts.push(meta);
    }

    instruction
        .accounts
        .extend_from_slice(&execute_instruction.accounts[5..]);
    instruction
        .accounts
        .push(AccountMeta::new_readonly(transfer_hook_program_id, false));
    instruction
        .accounts
        .push(AccountMeta::new_readonly(validation_account, false));
    Ok(())
}

fn de_escalate_account_meta(meta: &mut AccountMeta, existing: &[AccountMeta]) {
    if let Some(is_writable) = existing
        .iter()
        .filter(|existing_meta| existing_meta.pubkey == meta.pubkey)
        .map(|existing_meta| existing_meta.is_writable)
        .reduce(|acc, value| acc || value)
    {
        if !is_writable {
            meta.is_writable = false;
        }
    }
    meta.is_signer = false;
}

fn send_authority_instruction(
    rpc: &LiveRpc,
    payer: &Keypair,
    authority: &Keypair,
    instruction: Instruction,
) -> Result<String> {
    if payer.pubkey() == authority.pubkey() {
        rpc.send_and_confirm(&[instruction], &[payer])
    } else {
        rpc.send_and_confirm(&[instruction], &[payer, authority])
    }
}
