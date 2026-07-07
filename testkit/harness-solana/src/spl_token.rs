use std::str::FromStr;

use anyhow::{ensure, Context, Result};
use solana_address::Address;
use solana_instruction::{AccountMeta, Instruction};
use solana_keypair::Keypair;
use solana_signer::Signer;

use crate::live_rpc::LiveRpc;

pub const SPL_TOKEN_PROGRAM_ID: &str = "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA";
pub const ASSOCIATED_TOKEN_PROGRAM_ID: &str = "ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL";
pub const RENT_SYSVAR_ID: &str = "SysvarRent111111111111111111111111111111111";

pub const MINT_ACCOUNT_LEN: u64 = 82;

#[derive(Debug)]
pub struct TokenAccount {
    pub mint: Address,
    pub owner: Address,
    pub amount: u64,
}

#[derive(Debug)]
pub struct MintAccount {
    pub mint_authority: Option<Address>,
    pub supply: u64,
    pub decimals: u8,
    pub is_initialized: bool,
    pub freeze_authority: Option<Address>,
}

pub fn spl_token_program_id() -> Address {
    Address::from_str(SPL_TOKEN_PROGRAM_ID).expect("SPL Token program id is valid")
}

pub fn associated_token_program_id() -> Address {
    Address::from_str(ASSOCIATED_TOKEN_PROGRAM_ID).expect("Associated Token program id is valid")
}

pub fn rent_sysvar_id() -> Address {
    Address::from_str(RENT_SYSVAR_ID).expect("Rent sysvar id is valid")
}

pub fn create_mint(
    rpc: &LiveRpc,
    payer: &Keypair,
    decimals: u8,
    mint_authority: Address,
) -> Result<Keypair> {
    let token_program = spl_token_program_id();
    let mint = Keypair::new();
    let lamports = rpc.minimum_balance_for_rent_exemption(MINT_ACCOUNT_LEN)?;
    let create = solana_system_interface::instruction::create_account(
        &payer.pubkey(),
        &mint.pubkey(),
        lamports,
        MINT_ACCOUNT_LEN,
        &token_program,
    );
    let initialize = initialize_mint_instruction(mint.pubkey(), decimals, mint_authority);
    rpc.send_and_confirm(&[create, initialize], &[payer, &mint])
        .context("failed to create and initialize SPL Token mint")?;
    Ok(mint)
}

pub fn create_empty_associated_token_account(
    rpc: &LiveRpc,
    payer: &Keypair,
    wallet: Address,
    mint: Address,
) -> Result<Address> {
    let token_program = spl_token_program_id();
    let associated_token_program = associated_token_program_id();
    let account =
        associated_token_address(&wallet, &token_program, &mint, &associated_token_program);
    let create = create_associated_token_account_idempotent_instruction(
        payer.pubkey(),
        account,
        wallet,
        mint,
    );
    rpc.send_and_confirm(&[create], &[payer])
        .context("failed to create associated token account")?;
    let token_account = parse_token_account(&rpc.account_data(account)?)?;
    ensure!(
        token_account.mint == mint,
        "associated token account mint mismatch: expected {mint}, got {}",
        token_account.mint
    );
    ensure!(
        token_account.owner == wallet,
        "associated token account owner mismatch: expected {wallet}, got {}",
        token_account.owner
    );
    ensure!(
        token_account.amount == 0,
        "associated token account must be empty, got {}",
        token_account.amount
    );
    Ok(account)
}

pub fn mint_to(
    rpc: &LiveRpc,
    payer: &Keypair,
    mint: Address,
    destination: Address,
    authority: &Keypair,
    amount: u64,
) -> Result<String> {
    let instruction = mint_to_instruction(mint, destination, authority.pubkey(), amount);
    if payer.pubkey() == authority.pubkey() {
        rpc.send_and_confirm(&[instruction], &[payer])
    } else {
        rpc.send_and_confirm(&[instruction], &[payer, authority])
    }
    .context("failed to mint SPL Token amount")
}

pub fn associated_token_address(
    wallet: &Address,
    token_program: &Address,
    mint: &Address,
    associated_token_program: &Address,
) -> Address {
    Address::find_program_address(
        &[wallet.as_ref(), token_program.as_ref(), mint.as_ref()],
        associated_token_program,
    )
    .0
}

pub fn parse_token_account(data: &[u8]) -> Result<TokenAccount> {
    ensure!(
        data.len() >= 72,
        "token account data must be at least 72 bytes, got {}",
        data.len()
    );
    Ok(TokenAccount {
        mint: address_at(data, 0, "token account mint")?,
        owner: address_at(data, 32, "token account owner")?,
        amount: u64_at(data, 64, "token account amount")?,
    })
}

pub fn parse_mint_account(data: &[u8]) -> Result<MintAccount> {
    ensure!(
        data.len() >= MINT_ACCOUNT_LEN as usize,
        "mint account data must be at least {} bytes, got {}",
        MINT_ACCOUNT_LEN,
        data.len()
    );
    Ok(MintAccount {
        mint_authority: coption_address_at(data, 0, "mint authority")?,
        supply: u64_at(data, 36, "mint supply")?,
        decimals: data[44],
        is_initialized: data[45] != 0,
        freeze_authority: coption_address_at(data, 46, "freeze authority")?,
    })
}

pub fn create_system_wallet(rpc: &LiveRpc, payer: &Keypair) -> Result<Keypair> {
    let wallet = Keypair::new();
    let lamports = rpc.minimum_balance_for_rent_exemption(0)?;
    let ix = solana_system_interface::instruction::create_account(
        &payer.pubkey(),
        &wallet.pubkey(),
        lamports,
        0,
        &solana_system_interface::program::id(),
    );
    rpc.send_and_confirm(&[ix], &[payer, &wallet])
        .context("failed to create system wallet")?;
    Ok(wallet)
}

fn initialize_mint_instruction(
    mint: Address,
    decimals: u8,
    mint_authority: Address,
) -> Instruction {
    let mut data = Vec::with_capacity(35);
    data.push(0);
    data.push(decimals);
    data.extend_from_slice(mint_authority.as_ref());
    data.push(0);
    Instruction {
        program_id: spl_token_program_id(),
        accounts: vec![
            AccountMeta::new(mint, false),
            AccountMeta::new_readonly(rent_sysvar_id(), false),
        ],
        data,
    }
}

fn mint_to_instruction(
    mint: Address,
    destination: Address,
    authority: Address,
    amount: u64,
) -> Instruction {
    let mut data = Vec::with_capacity(9);
    data.push(7);
    data.extend_from_slice(&amount.to_le_bytes());
    Instruction {
        program_id: spl_token_program_id(),
        accounts: vec![
            AccountMeta::new(mint, false),
            AccountMeta::new(destination, false),
            AccountMeta::new_readonly(authority, true),
        ],
        data,
    }
}

fn create_associated_token_account_idempotent_instruction(
    payer: Address,
    account: Address,
    wallet: Address,
    mint: Address,
) -> Instruction {
    Instruction {
        program_id: associated_token_program_id(),
        accounts: vec![
            AccountMeta::new(payer, true),
            AccountMeta::new(account, false),
            AccountMeta::new_readonly(wallet, false),
            AccountMeta::new_readonly(mint, false),
            AccountMeta::new_readonly(solana_system_interface::program::id(), false),
            AccountMeta::new_readonly(spl_token_program_id(), false),
        ],
        data: vec![1],
    }
}

fn coption_address_at(data: &[u8], offset: usize, label: &str) -> Result<Option<Address>> {
    let tag = u32_at(data, offset, label)?;
    match tag {
        0 => Ok(None),
        1 => Ok(Some(address_at(data, offset + 4, label)?)),
        _ => anyhow::bail!("{label} has invalid COption tag {tag}"),
    }
}

fn address_at(data: &[u8], offset: usize, label: &str) -> Result<Address> {
    let end = offset.checked_add(32).context("address offset overflow")?;
    let bytes: [u8; 32] = data
        .get(offset..end)
        .with_context(|| format!("{label} requires bytes {offset}..{end}"))?
        .try_into()
        .expect("slice length is fixed");
    Ok(Address::from(bytes))
}

fn u32_at(data: &[u8], offset: usize, label: &str) -> Result<u32> {
    let end = offset.checked_add(4).context("u32 offset overflow")?;
    let bytes: [u8; 4] = data
        .get(offset..end)
        .with_context(|| format!("{label} requires bytes {offset}..{end}"))?
        .try_into()
        .expect("slice length is fixed");
    Ok(u32::from_le_bytes(bytes))
}

fn u64_at(data: &[u8], offset: usize, label: &str) -> Result<u64> {
    let end = offset.checked_add(8).context("u64 offset overflow")?;
    let bytes: [u8; 8] = data
        .get(offset..end)
        .with_context(|| format!("{label} requires bytes {offset}..{end}"))?
        .try_into()
        .expect("slice length is fixed");
    Ok(u64::from_le_bytes(bytes))
}
