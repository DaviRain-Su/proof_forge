use std::str::FromStr;

use anyhow::{anyhow, ensure, Context, Result};
use solana_address::Address;
use solana_instruction::Instruction;
use solana_keypair::Keypair;
use solana_signer::Signer;
use spl_token_2022_interface::{
    extension::{
        immutable_owner::ImmutableOwner,
        non_transferable::{NonTransferable, NonTransferableAccount},
        BaseStateWithExtensions, ExtensionType, StateWithExtensions,
    },
    instruction as token_instruction,
    state::{Account as Token2022AccountState, Mint as Token2022MintState},
};

use crate::{
    live_rpc::LiveRpc,
    spl_token::{
        create_empty_associated_token_account_for_program, parse_mint_account, parse_token_account,
        MintAccount, TokenAccount,
    },
};

pub const TOKEN_2022_PROGRAM_ID: &str = "TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb";

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
