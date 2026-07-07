use std::collections::HashSet;
use std::env;
use std::str::FromStr;

use anyhow::{ensure, Context, Result};
use proof_forge_testkit_harness_solana::live_rpc::{read_keypair, LiveRpc};
use proof_forge_testkit_harness_solana::spl_token::{
    create_funded_system_wallet, create_system_wallet,
};
use proof_forge_testkit_harness_solana::token_2022::{
    assert_transfer_hook_config, create_empty_associated_token_account,
    create_transfer_hook_mint_account, expect_transfer_checked_with_hook_failure,
    initialize_transfer_hook_mint, mint_to, parse_account, parse_mint, token_2022_program_id,
    transfer_checked_with_hook_instruction, transfer_hook_extra_account_meta_address,
    transfer_hook_extra_account_meta_space, transfer_hook_extra_account_metas,
};
use serde_json::json;
use solana_address::Address;
use solana_instruction::{AccountMeta, Instruction};
use solana_signer::Signer;

fn main() {
    if let Err(err) = run() {
        eprintln!("{err:#}");
        std::process::exit(1);
    }
}

fn run() -> Result<()> {
    let rpc_url =
        env::var("PROOF_FORGE_SOLANA_RPC_URL").context("missing PROOF_FORGE_SOLANA_RPC_URL")?;
    let payer_path =
        env::var("PROOF_FORGE_SOLANA_PAYER").context("missing PROOF_FORGE_SOLANA_PAYER")?;
    let program_id_value = env::var("PROOF_FORGE_SOLANA_PROGRAM_ID")
        .context("missing PROOF_FORGE_SOLANA_PROGRAM_ID")?;
    let decimals = env_u8("PROOF_FORGE_SOLANA_TOKEN_DECIMALS", 0)?;
    let initial_supply = env_u64("PROOF_FORGE_SOLANA_TOKEN_INITIAL_SUPPLY", 100)?;
    let allowed_amount = env_u64("PROOF_FORGE_SOLANA_TRANSFER_HOOK_ALLOWED_AMOUNT", 10)?;
    let rejected_amount = env_u64("PROOF_FORGE_SOLANA_TRANSFER_HOOK_REJECTED_AMOUNT", 60)?;
    ensure!(
        allowed_amount <= 50,
        "allowed amount must satisfy generated hook cap: {allowed_amount}"
    );
    ensure!(
        rejected_amount > 50,
        "rejected amount must exceed generated hook cap: {rejected_amount}"
    );
    ensure!(
        initial_supply >= allowed_amount.saturating_add(rejected_amount),
        "initial supply too small: {initial_supply}"
    );

    let rpc = LiveRpc::new(rpc_url);
    let payer = read_keypair(&payer_path)?;
    let program_id = Address::from_str(&program_id_value)
        .with_context(|| format!("invalid program id {program_id_value}"))?;

    let mint = create_transfer_hook_mint_account(&rpc, &payer)
        .context("failed to create transfer-hook mint account")?;
    let sentinel = create_system_wallet(&rpc, &payer).context("failed to create sentinel")?;
    let init_authority =
        create_system_wallet(&rpc, &payer).context("failed to create init authority")?;
    let (extra_account_meta_list, bump) =
        transfer_hook_extra_account_meta_address(mint.pubkey(), program_id);
    let initialize_mint_signature = initialize_transfer_hook_mint(
        &rpc,
        &payer,
        mint.pubkey(),
        decimals,
        payer.pubkey(),
        payer.pubkey(),
        program_id,
    )
    .context("failed to initialize transfer-hook mint")?;
    let mut mint_data = rpc.account_data(mint.pubkey())?;
    let mint_account = parse_mint(&mint_data)?;
    ensure!(
        mint_account.is_initialized,
        "transfer-hook mint should be initialized"
    );
    ensure!(
        mint_account.decimals == decimals,
        "transfer-hook mint decimals mismatch: expected {decimals}, got {}",
        mint_account.decimals
    );
    assert_transfer_hook_config(&mint_data, payer.pubkey(), program_id)?;

    let source_ata =
        create_empty_associated_token_account(&rpc, &payer, payer.pubkey(), mint.pubkey())
            .context("failed to create source Token-2022 ATA")?;
    let destination_owner =
        create_system_wallet(&rpc, &payer).context("failed to create destination owner")?;
    let destination_ata = create_empty_associated_token_account(
        &rpc,
        &payer,
        destination_owner.pubkey(),
        mint.pubkey(),
    )
    .context("failed to create destination Token-2022 ATA")?;
    let mint_to_signature = mint_to(
        &rpc,
        &payer,
        mint.pubkey(),
        source_ata,
        &payer,
        initial_supply,
    )
    .context("failed to mint initial supply")?;

    let extra_meta_space = transfer_hook_extra_account_meta_space(2)? as u64;
    ensure!(
        extra_meta_space == 86,
        "transfer-hook extra-account-meta space mismatch: expected 86, got {extra_meta_space}"
    );
    let rent_lamports = rpc.minimum_balance_for_rent_exemption(extra_meta_space)?;
    let init_source = create_funded_system_wallet(
        &rpc,
        &payer,
        rent_lamports
            .checked_add(1_000_000)
            .context("init source lamports overflow")?,
    )
    .context("failed to create funded init source")?;
    let initialize_extra_metas_signature = rpc
        .send_and_confirm(
            &[generated_initialize_extra_metas_instruction(
                program_id,
                init_source.pubkey(),
                mint.pubkey(),
                destination_ata,
                init_authority.pubkey(),
                extra_account_meta_list,
                sentinel.pubkey(),
                rent_lamports,
                extra_meta_space,
                bump,
            )],
            &[&payer, &init_source],
        )
        .context("generated initialize_extra_account_meta_list failed")?;

    let validation_account = rpc
        .account_info(extra_account_meta_list)
        .context("failed to read transfer-hook validation account")?;
    ensure!(
        validation_account.owner == program_id,
        "validation account owner mismatch: expected {program_id}, got {}",
        validation_account.owner
    );
    ensure!(
        validation_account.data.len() == extra_meta_space as usize,
        "validation account size mismatch: expected {extra_meta_space}, got {}",
        validation_account.data.len()
    );
    let extra_metas = transfer_hook_extra_account_metas(&validation_account.data)?;
    ensure!(
        extra_metas.len() == 2,
        "expected two extra metas, got {}",
        extra_metas.len()
    );
    ensure!(
        extra_metas[0].address == sentinel.pubkey(),
        "sentinel route mismatch: expected {}, got {}",
        sentinel.pubkey(),
        extra_metas[0].address
    );
    ensure!(
        extra_metas[1].address == solana_system_interface::program::id(),
        "system program route mismatch: expected {}, got {}",
        solana_system_interface::program::id(),
        extra_metas[1].address
    );
    for (idx, meta) in extra_metas.iter().enumerate() {
        ensure!(
            meta.discriminator == 0,
            "extra meta {idx} discriminator mismatch: {}",
            meta.discriminator
        );
        ensure!(!meta.is_signer, "extra meta {idx} signer should be false");
        ensure!(
            !meta.is_writable,
            "extra meta {idx} writable should be false"
        );
    }

    let allowed_instruction = transfer_checked_with_hook_instruction(
        &rpc,
        source_ata,
        mint.pubkey(),
        destination_ata,
        payer.pubkey(),
        program_id,
        allowed_amount,
        decimals,
    )?;
    let allowed_keys = pubkey_set(&allowed_instruction);
    for routed in [
        sentinel.pubkey(),
        solana_system_interface::program::id(),
        program_id,
        extra_account_meta_list,
    ] {
        ensure!(
            allowed_keys.contains(&routed),
            "transfer instruction missing routed account {routed}"
        );
    }
    let allowed_transfer_signature = rpc
        .send_and_confirm(&[allowed_instruction], &[&payer])
        .context("allowed transfer-hook transfer failed")?;

    let mut source_account = parse_account(&rpc.account_data(source_ata)?)?;
    let mut destination_account = parse_account(&rpc.account_data(destination_ata)?)?;
    ensure!(
        source_account.amount == initial_supply - allowed_amount,
        "source after allowed transfer mismatch: expected {}, got {}",
        initial_supply - allowed_amount,
        source_account.amount
    );
    ensure!(
        destination_account.amount == allowed_amount,
        "destination after allowed transfer mismatch: expected {allowed_amount}, got {}",
        destination_account.amount
    );

    let reject_failure = expect_transfer_checked_with_hook_failure(
        &rpc,
        &payer,
        source_ata,
        mint.pubkey(),
        destination_ata,
        &payer,
        program_id,
        rejected_amount,
        decimals,
    )
    .context("expected rejected transfer-hook transfer to fail")?;
    source_account = parse_account(&rpc.account_data(source_ata)?)?;
    destination_account = parse_account(&rpc.account_data(destination_ata)?)?;
    ensure!(
        source_account.amount == initial_supply - allowed_amount,
        "source changed after rejected transfer: {}",
        source_account.amount
    );
    ensure!(
        destination_account.amount == allowed_amount,
        "destination changed after rejected transfer: {}",
        destination_account.amount
    );
    mint_data = rpc.account_data(mint.pubkey())?;
    assert_transfer_hook_config(&mint_data, payer.pubkey(), program_id)?;

    println!(
        "{}",
        json!({
            "programId": program_id.to_string(),
            "payer": payer.pubkey().to_string(),
            "mint": mint.pubkey().to_string(),
            "source": source_ata.to_string(),
            "destination": destination_ata.to_string(),
            "extraAccountMetaList": extra_account_meta_list.to_string(),
            "sentinel": sentinel.pubkey().to_string(),
            "initAuthority": init_authority.pubkey().to_string(),
            "initSource": init_source.pubkey().to_string(),
            "tokenProgram": token_2022_program_id().to_string(),
            "allowedAmount": allowed_amount.to_string(),
            "rejectedAmount": rejected_amount.to_string(),
            "sourceAmount": source_account.amount.to_string(),
            "destinationAmount": destination_account.amount.to_string(),
            "extraMetaCount": extra_metas.len(),
            "rejectError": reject_failure.err,
            "rejectSignature": reject_failure.signature,
            "signatures": {
                "initializeMint": initialize_mint_signature,
                "mintTo": mint_to_signature,
                "initializeExtraMetas": initialize_extra_metas_signature,
                "allowedTransfer": allowed_transfer_signature,
            },
        })
    );

    Ok(())
}

fn generated_initialize_extra_metas_instruction(
    program_id: Address,
    source: Address,
    mint: Address,
    destination: Address,
    authority: Address,
    extra_account_meta_list: Address,
    sentinel: Address,
    rent_lamports: u64,
    extra_meta_space: u64,
    bump: u8,
) -> Instruction {
    Instruction {
        program_id,
        accounts: vec![
            AccountMeta::new(source, true),
            AccountMeta::new_readonly(mint, false),
            AccountMeta::new_readonly(destination, false),
            AccountMeta::new_readonly(authority, false),
            AccountMeta::new(extra_account_meta_list, false),
            AccountMeta::new_readonly(sentinel, false),
            AccountMeta::new_readonly(solana_system_interface::program::id(), false),
        ],
        data: initialize_extra_metas_data(rent_lamports, extra_meta_space, bump),
    }
}

fn initialize_extra_metas_data(rent_lamports: u64, extra_meta_space: u64, bump: u8) -> Vec<u8> {
    let mut data = vec![0; 25];
    data[0] = 0;
    data[1..9].copy_from_slice(&rent_lamports.to_le_bytes());
    data[9..17].copy_from_slice(&extra_meta_space.to_le_bytes());
    data[17..25].copy_from_slice(&(u64::from(bump)).to_le_bytes());
    data
}

fn pubkey_set(instruction: &Instruction) -> HashSet<Address> {
    instruction
        .accounts
        .iter()
        .map(|meta| meta.pubkey)
        .collect()
}

fn env_u8(name: &str, default: u8) -> Result<u8> {
    env::var(name)
        .ok()
        .map(|value| {
            value
                .parse::<u8>()
                .with_context(|| format!("invalid {name}={value}"))
        })
        .transpose()
        .map(|value| value.unwrap_or(default))
}

fn env_u64(name: &str, default: u64) -> Result<u64> {
    env::var(name)
        .ok()
        .map(|value| {
            value
                .parse::<u64>()
                .with_context(|| format!("invalid {name}={value}"))
        })
        .transpose()
        .map(|value| value.unwrap_or(default))
}
