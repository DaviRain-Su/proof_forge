#![recursion_limit = "256"]

use std::collections::HashMap;
use std::env;
use std::fs;
use std::path::PathBuf;
use std::str::FromStr;

use anyhow::{anyhow, ensure, Context, Result};
use proof_forge_testkit_harness_solana::live_rpc::{
    create_program_state, read_keypair, read_u64_le_at, LiveRpc,
};
use proof_forge_testkit_harness_solana::spl_token::create_system_wallet;
use proof_forge_testkit_harness_solana::token_2022::{
    account_withheld_amount, assert_default_account_state, assert_immutable_owner_account,
    assert_interest_bearing_config, assert_memo_transfer, assert_metadata_pointer_config,
    assert_non_transferable_mint, assert_permanent_delegate, assert_transfer_fee_config,
    assert_transfer_hook_config, calculate_epoch_fee, create_empty_associated_token_account,
    create_mint_account_with_extensions, create_token_account_with_extensions, initialize_account,
    initialize_mint, initialize_mint_with_freeze_authority, mint_to, mint_withheld_amount,
    parse_account, parse_mint, token_2022_program_id,
};
use serde::Deserialize;
use serde_json::json;
use solana_address::Address;
use solana_instruction::{AccountMeta, Instruction};
use solana_keypair::Keypair;
use solana_signer::Signer;
use spl_token_2022_interface::{extension::ExtensionType, state::AccountState};

const STATE_SPACE: u64 = 40;
const ACCOUNT_STATE_FROZEN: AccountState = AccountState::Frozen;
const ACCOUNT_STATE_FROZEN_U64: u64 = 2;
const INTEREST_RATE_BASIS_POINTS: i16 = 250;

#[derive(Debug, Deserialize)]
struct Artifact {
    #[serde(default, rename = "solanaInstructions")]
    solana_instructions: Vec<ArtifactInstruction>,
}

#[derive(Debug, Deserialize)]
struct ArtifactInstruction {
    name: String,
    #[serde(default)]
    accounts: Vec<ArtifactAccount>,
}

#[derive(Debug, Deserialize)]
struct ArtifactAccount {
    name: String,
    #[serde(default)]
    signer: bool,
    #[serde(default)]
    writable: bool,
}

struct GeneratedAccounts {
    state: Address,
    transfer_fee_mint: Address,
    token_owner: Address,
    withdraw_withheld_authority: Address,
    transfer_fee_config_authority: Address,
    scratch_source: Address,
    scratch_destination: Address,
    scratch_fee_receiver: Address,
    scratch_withheld_source: Address,
    non_transferable_mint: Address,
    metadata_pointer_mint: Address,
    default_state_mint: Address,
    immutable_owner_account: Address,
    permanent_delegate_mint: Address,
    interest_bearing_mint: Address,
    memo_transfer_account: Address,
    transfer_hook_mint: Address,
    metadata_pointer_authority: Address,
    metadata_address: Address,
    permanent_delegate: Address,
    interest_rate_authority: Address,
    transfer_hook_authority: Address,
    transfer_hook_program: Address,
}

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
    let artifact_path =
        env::var("PROOF_FORGE_SOLANA_ARTIFACT").context("missing PROOF_FORGE_SOLANA_ARTIFACT")?;
    let artifact = load_artifact(PathBuf::from(artifact_path))?;

    let decimals = env_u8("PROOF_FORGE_SOLANA_TOKEN_DECIMALS", 9)?;
    let initial_supply = env_u64("PROOF_FORGE_SOLANA_TOKEN_INITIAL_SUPPLY", 1_000_000_000)?;
    let transfer_fee_basis_points = env_u64("PROOF_FORGE_SOLANA_TRANSFER_FEE_BPS", 125)?;
    let maximum_fee = env_u64("PROOF_FORGE_SOLANA_TRANSFER_FEE_MAX_FEE", 10_000)?;
    let next_basis_points = env_u64("PROOF_FORGE_SOLANA_TRANSFER_FEE_NEXT_BPS", 250)?;
    let next_maximum_fee = env_u64("PROOF_FORGE_SOLANA_TRANSFER_FEE_NEXT_MAX_FEE", 20_000)?;
    let transfer_amount = env_u64("PROOF_FORGE_SOLANA_TOKEN_TRANSFER_AMOUNT", 250_000)?;
    ensure!(
        initial_supply > transfer_amount.saturating_mul(2),
        "initial supply {initial_supply} is too small for two transfers of {transfer_amount}"
    );
    ensure!(
        transfer_fee_basis_points <= 10_000,
        "invalid basis points: {transfer_fee_basis_points}"
    );
    ensure!(
        next_basis_points <= 10_000,
        "invalid next basis points: {next_basis_points}"
    );

    let rpc = LiveRpc::new(rpc_url);
    let payer = read_keypair(&payer_path)?;
    let program_id = Address::from_str(&program_id_value)
        .with_context(|| format!("invalid program id {program_id_value}"))?;
    let state = create_program_state(&rpc, &payer, program_id, STATE_SPACE)
        .context("failed to create program state account")?;

    let transfer_fee_mint = create_mint_account_with_extensions(
        &rpc,
        &payer,
        &[ExtensionType::TransferFeeConfig],
        "transfer-fee",
    )?;
    let metadata_pointer_mint = create_mint_account_with_extensions(
        &rpc,
        &payer,
        &[ExtensionType::MetadataPointer],
        "metadata-pointer",
    )?;
    let default_state_mint = create_mint_account_with_extensions(
        &rpc,
        &payer,
        &[ExtensionType::DefaultAccountState],
        "default-state",
    )?;
    let immutable_owner_mint =
        create_mint_account_with_extensions(&rpc, &payer, &[], "immutable-owner")?;
    let immutable_owner_account = create_token_account_with_extensions(
        &rpc,
        &payer,
        &[ExtensionType::ImmutableOwner],
        "immutable-owner",
    )?;
    let non_transferable_mint = create_mint_account_with_extensions(
        &rpc,
        &payer,
        &[ExtensionType::NonTransferable],
        "non-transferable",
    )?;
    let permanent_delegate_mint = create_mint_account_with_extensions(
        &rpc,
        &payer,
        &[ExtensionType::PermanentDelegate],
        "permanent-delegate",
    )?;
    let interest_bearing_mint = create_mint_account_with_extensions(
        &rpc,
        &payer,
        &[ExtensionType::InterestBearingConfig],
        "interest-bearing",
    )?;
    let memo_transfer_mint =
        create_mint_account_with_extensions(&rpc, &payer, &[], "memo-transfer")?;
    let memo_transfer_account = create_token_account_with_extensions(
        &rpc,
        &payer,
        &[ExtensionType::MemoTransfer],
        "memo-transfer",
    )?;
    let transfer_hook_mint = create_mint_account_with_extensions(
        &rpc,
        &payer,
        &[ExtensionType::TransferHook],
        "transfer-hook",
    )?;

    let token_owner = create_system_wallet(&rpc, &payer)?;
    let withdraw_withheld_authority = create_system_wallet(&rpc, &payer)?;
    let transfer_fee_config_authority = create_system_wallet(&rpc, &payer)?;
    let metadata_pointer_authority = create_system_wallet(&rpc, &payer)?;
    let metadata_address = create_system_wallet(&rpc, &payer)?;
    let permanent_delegate = create_system_wallet(&rpc, &payer)?;
    let interest_rate_authority = create_system_wallet(&rpc, &payer)?;
    let transfer_hook_authority = create_system_wallet(&rpc, &payer)?;
    let transfer_hook_program = create_system_wallet(&rpc, &payer)?;
    let scratch_source = create_system_wallet(&rpc, &payer)?;
    let scratch_destination = create_system_wallet(&rpc, &payer)?;
    let scratch_fee_receiver = create_system_wallet(&rpc, &payer)?;
    let scratch_withheld_source = create_system_wallet(&rpc, &payer)?;

    let accounts = GeneratedAccounts {
        state: state.pubkey(),
        transfer_fee_mint: transfer_fee_mint.pubkey(),
        token_owner: token_owner.pubkey(),
        withdraw_withheld_authority: withdraw_withheld_authority.pubkey(),
        transfer_fee_config_authority: transfer_fee_config_authority.pubkey(),
        scratch_source: scratch_source.pubkey(),
        scratch_destination: scratch_destination.pubkey(),
        scratch_fee_receiver: scratch_fee_receiver.pubkey(),
        scratch_withheld_source: scratch_withheld_source.pubkey(),
        non_transferable_mint: non_transferable_mint.pubkey(),
        metadata_pointer_mint: metadata_pointer_mint.pubkey(),
        default_state_mint: default_state_mint.pubkey(),
        immutable_owner_account: immutable_owner_account.pubkey(),
        permanent_delegate_mint: permanent_delegate_mint.pubkey(),
        interest_bearing_mint: interest_bearing_mint.pubkey(),
        memo_transfer_account: memo_transfer_account.pubkey(),
        transfer_hook_mint: transfer_hook_mint.pubkey(),
        metadata_pointer_authority: metadata_pointer_authority.pubkey(),
        metadata_address: metadata_address.pubkey(),
        permanent_delegate: permanent_delegate.pubkey(),
        interest_rate_authority: interest_rate_authority.pubkey(),
        transfer_hook_authority: transfer_hook_authority.pubkey(),
        transfer_hook_program: transfer_hook_program.pubkey(),
    };
    let known_signers = [
        &token_owner,
        &withdraw_withheld_authority,
        &transfer_fee_config_authority,
    ];

    let init_fee_signature = invoke_generated(
        &rpc,
        &payer,
        program_id,
        instruction(&artifact, "init_fee_config")?,
        pubkeys_for(&accounts, &[]),
        write_data(0, &[transfer_fee_basis_points, maximum_fee]),
        &known_signers,
    )?;
    assert_state_value(
        &rpc,
        state.pubkey(),
        16,
        transfer_fee_basis_points,
        "last_basis_points after init",
    )?;
    assert_state_value(
        &rpc,
        state.pubkey(),
        24,
        maximum_fee,
        "last_maximum_fee after init",
    )?;

    let initialize_mint_signature = initialize_mint(
        &rpc,
        &payer,
        transfer_fee_mint.pubkey(),
        decimals,
        payer.pubkey(),
    )?;
    let mut mint_data = rpc.account_data(transfer_fee_mint.pubkey())?;
    assert_transfer_fee_config(
        &mint_data,
        transfer_fee_config_authority.pubkey(),
        withdraw_withheld_authority.pubkey(),
        u16::try_from(transfer_fee_basis_points).context("basis points must fit in u16")?,
        maximum_fee,
    )?;
    let mint_account = parse_mint(&mint_data)?;
    ensure!(
        mint_account.is_initialized,
        "transfer-fee mint should be initialized"
    );

    let recipient = Keypair::new();
    let harvest_recipient = Keypair::new();
    let fee_receiver = Keypair::new();
    let owner_ata = create_empty_associated_token_account(
        &rpc,
        &payer,
        token_owner.pubkey(),
        transfer_fee_mint.pubkey(),
    )?;
    let recipient_ata = create_empty_associated_token_account(
        &rpc,
        &payer,
        recipient.pubkey(),
        transfer_fee_mint.pubkey(),
    )?;
    let harvest_recipient_ata = create_empty_associated_token_account(
        &rpc,
        &payer,
        harvest_recipient.pubkey(),
        transfer_fee_mint.pubkey(),
    )?;
    let fee_receiver_ata = create_empty_associated_token_account(
        &rpc,
        &payer,
        fee_receiver.pubkey(),
        transfer_fee_mint.pubkey(),
    )?;

    let mint_to_signature = mint_to(
        &rpc,
        &payer,
        transfer_fee_mint.pubkey(),
        owner_ata,
        &payer,
        initial_supply,
    )?;
    assert_amount(
        "owner after mint",
        parse_account(&rpc.account_data(owner_ata)?)?.amount,
        initial_supply,
    )?;
    assert_amount(
        "recipient initial",
        parse_account(&rpc.account_data(recipient_ata)?)?.amount,
        0,
    )?;
    assert_amount(
        "harvest recipient initial",
        parse_account(&rpc.account_data(harvest_recipient_ata)?)?.amount,
        0,
    )?;
    assert_amount(
        "fee receiver initial",
        parse_account(&rpc.account_data(fee_receiver_ata)?)?.amount,
        0,
    )?;

    let epoch = rpc.epoch_info()?.epoch;
    let expected_fee = calculate_epoch_fee(&mint_data, epoch, transfer_amount)?;
    let transfer_signature = invoke_generated(
        &rpc,
        &payer,
        program_id,
        instruction(&artifact, "transfer_with_fee")?,
        pubkeys_for(
            &accounts,
            &[
                ("source", owner_ata),
                ("destination", recipient_ata),
                ("fee_receiver", fee_receiver_ata),
            ],
        ),
        write_data(1, &[transfer_amount, expected_fee]),
        &known_signers,
    )?;
    let mut owner_account = parse_account(&rpc.account_data(owner_ata)?)?;
    let mut recipient_account = parse_account(&rpc.account_data(recipient_ata)?)?;
    assert_amount(
        "owner after generated transfer_with_fee",
        owner_account.amount,
        initial_supply - transfer_amount,
    )?;
    assert_amount(
        "recipient after generated transfer_with_fee",
        recipient_account.amount,
        transfer_amount - expected_fee,
    )?;
    assert_amount(
        "recipient withheld transfer fee",
        account_withheld_amount(&rpc.account_data(recipient_ata)?, "recipient")?,
        expected_fee,
    )?;
    assert_state_value(
        &rpc,
        state.pubkey(),
        0,
        transfer_amount,
        "last_amount after transfer",
    )?;
    assert_state_value(
        &rpc,
        state.pubkey(),
        8,
        expected_fee,
        "last_fee after transfer",
    )?;

    let withdraw_from_accounts_signature = invoke_generated(
        &rpc,
        &payer,
        program_id,
        instruction(&artifact, "withdraw_from_accounts")?,
        pubkeys_for(
            &accounts,
            &[
                ("fee_receiver", fee_receiver_ata),
                ("withheld_source", recipient_ata),
            ],
        ),
        write_data(3, &[]),
        &known_signers,
    )?;
    recipient_account = parse_account(&rpc.account_data(recipient_ata)?)?;
    let mut fee_receiver_account = parse_account(&rpc.account_data(fee_receiver_ata)?)?;
    assert_amount(
        "recipient withheld fee after generated withdraw_from_accounts",
        account_withheld_amount(&rpc.account_data(recipient_ata)?, "recipient")?,
        0,
    )?;
    assert_amount(
        "fee receiver after generated withdraw_from_accounts",
        fee_receiver_account.amount,
        expected_fee,
    )?;
    assert_state_value(
        &rpc,
        state.pubkey(),
        32,
        2,
        "marker after withdraw_from_accounts",
    )?;

    let harvest_transfer_signature = invoke_generated(
        &rpc,
        &payer,
        program_id,
        instruction(&artifact, "transfer_with_fee")?,
        pubkeys_for(
            &accounts,
            &[
                ("source", owner_ata),
                ("destination", harvest_recipient_ata),
                ("fee_receiver", fee_receiver_ata),
            ],
        ),
        write_data(1, &[transfer_amount, expected_fee]),
        &known_signers,
    )?;
    owner_account = parse_account(&rpc.account_data(owner_ata)?)?;
    let mut harvest_recipient_account = parse_account(&rpc.account_data(harvest_recipient_ata)?)?;
    assert_amount(
        "owner after harvest-path generated transfer",
        owner_account.amount,
        initial_supply - transfer_amount * 2,
    )?;
    assert_amount(
        "harvest recipient after generated transfer_with_fee",
        harvest_recipient_account.amount,
        transfer_amount - expected_fee,
    )?;
    assert_amount(
        "harvest recipient withheld fee",
        account_withheld_amount(
            &rpc.account_data(harvest_recipient_ata)?,
            "harvest recipient",
        )?,
        expected_fee,
    )?;

    let harvest_to_mint_signature = invoke_generated(
        &rpc,
        &payer,
        program_id,
        instruction(&artifact, "harvest_to_mint")?,
        pubkeys_for(
            &accounts,
            &[
                ("fee_receiver", fee_receiver_ata),
                ("withheld_source", harvest_recipient_ata),
            ],
        ),
        write_data(4, &[]),
        &known_signers,
    )?;
    harvest_recipient_account = parse_account(&rpc.account_data(harvest_recipient_ata)?)?;
    mint_data = rpc.account_data(transfer_fee_mint.pubkey())?;
    assert_amount(
        "harvest recipient withheld fee after generated harvest_to_mint",
        account_withheld_amount(
            &rpc.account_data(harvest_recipient_ata)?,
            "harvest recipient",
        )?,
        0,
    )?;
    assert_amount(
        "mint withheld fee after generated harvest_to_mint",
        mint_withheld_amount(&mint_data)?,
        expected_fee,
    )?;
    assert_state_value(&rpc, state.pubkey(), 32, 3, "marker after harvest_to_mint")?;

    let withdraw_from_mint_signature = invoke_generated(
        &rpc,
        &payer,
        program_id,
        instruction(&artifact, "withdraw_from_mint")?,
        pubkeys_for(&accounts, &[("fee_receiver", fee_receiver_ata)]),
        write_data(2, &[]),
        &known_signers,
    )?;
    fee_receiver_account = parse_account(&rpc.account_data(fee_receiver_ata)?)?;
    mint_data = rpc.account_data(transfer_fee_mint.pubkey())?;
    assert_amount(
        "fee receiver after generated withdraw_from_mint",
        fee_receiver_account.amount,
        expected_fee * 2,
    )?;
    assert_amount(
        "mint withheld fee after generated withdraw_from_mint",
        mint_withheld_amount(&mint_data)?,
        0,
    )?;
    assert_state_value(
        &rpc,
        state.pubkey(),
        32,
        1,
        "marker after withdraw_from_mint",
    )?;

    let set_fee_signature = invoke_generated(
        &rpc,
        &payer,
        program_id,
        instruction(&artifact, "set_transfer_fee")?,
        pubkeys_for(&accounts, &[("fee_receiver", fee_receiver_ata)]),
        write_data(5, &[next_basis_points, next_maximum_fee]),
        &known_signers,
    )?;
    mint_data = rpc.account_data(transfer_fee_mint.pubkey())?;
    assert_transfer_fee_config(
        &mint_data,
        transfer_fee_config_authority.pubkey(),
        withdraw_withheld_authority.pubkey(),
        u16::try_from(next_basis_points).context("next basis points must fit in u16")?,
        next_maximum_fee,
    )?;
    assert_state_value(
        &rpc,
        state.pubkey(),
        16,
        next_basis_points,
        "last_basis_points after set",
    )?;
    assert_state_value(
        &rpc,
        state.pubkey(),
        24,
        next_maximum_fee,
        "last_maximum_fee after set",
    )?;

    let init_non_transferable_signature = invoke_generated(
        &rpc,
        &payer,
        program_id,
        instruction(&artifact, "initialize_non_transferable")?,
        pubkeys_for(&accounts, &[]),
        write_data(6, &[]),
        &known_signers,
    )?;
    let initialize_non_transferable_mint_signature = initialize_mint(
        &rpc,
        &payer,
        non_transferable_mint.pubkey(),
        decimals,
        payer.pubkey(),
    )?;
    assert_non_transferable_mint(&rpc.account_data(non_transferable_mint.pubkey())?)?;
    assert_state_value(
        &rpc,
        state.pubkey(),
        32,
        4,
        "marker after initialize_non_transferable",
    )?;

    let init_metadata_pointer_signature = invoke_generated(
        &rpc,
        &payer,
        program_id,
        instruction(&artifact, "initialize_metadata_pointer")?,
        pubkeys_for(&accounts, &[]),
        write_data(7, &[]),
        &known_signers,
    )?;
    let initialize_metadata_pointer_mint_signature = initialize_mint(
        &rpc,
        &payer,
        metadata_pointer_mint.pubkey(),
        decimals,
        payer.pubkey(),
    )?;
    assert_metadata_pointer_config(
        &rpc.account_data(metadata_pointer_mint.pubkey())?,
        metadata_pointer_authority.pubkey(),
        metadata_address.pubkey(),
    )?;
    assert_state_value(
        &rpc,
        state.pubkey(),
        32,
        5,
        "marker after initialize_metadata_pointer",
    )?;

    let init_default_account_state_signature = invoke_generated(
        &rpc,
        &payer,
        program_id,
        instruction(&artifact, "initialize_default_account_state")?,
        pubkeys_for(&accounts, &[]),
        write_data(8, &[]),
        &known_signers,
    )?;
    let initialize_default_state_mint_signature = initialize_mint_with_freeze_authority(
        &rpc,
        &payer,
        default_state_mint.pubkey(),
        decimals,
        payer.pubkey(),
        Some(payer.pubkey()),
    )?;
    assert_default_account_state(
        &rpc.account_data(default_state_mint.pubkey())?,
        ACCOUNT_STATE_FROZEN,
    )?;
    assert_state_value(
        &rpc,
        state.pubkey(),
        32,
        6,
        "marker after initialize_default_account_state",
    )?;

    let initialize_immutable_owner_mint_signature = initialize_mint(
        &rpc,
        &payer,
        immutable_owner_mint.pubkey(),
        decimals,
        payer.pubkey(),
    )?;
    let init_immutable_owner_signature = invoke_generated(
        &rpc,
        &payer,
        program_id,
        instruction(&artifact, "initialize_immutable_owner")?,
        pubkeys_for(&accounts, &[]),
        write_data(9, &[]),
        &known_signers,
    )?;
    let initialize_immutable_owner_account_signature = initialize_account(
        &rpc,
        &payer,
        immutable_owner_account.pubkey(),
        immutable_owner_mint.pubkey(),
        token_owner.pubkey(),
    )?;
    assert_immutable_owner_account(&rpc.account_data(immutable_owner_account.pubkey())?)?;
    assert_state_value(
        &rpc,
        state.pubkey(),
        32,
        7,
        "marker after initialize_immutable_owner",
    )?;

    let init_permanent_delegate_signature = invoke_generated(
        &rpc,
        &payer,
        program_id,
        instruction(&artifact, "initialize_permanent_delegate")?,
        pubkeys_for(&accounts, &[]),
        write_data(10, &[]),
        &known_signers,
    )?;
    let initialize_permanent_delegate_mint_signature = initialize_mint(
        &rpc,
        &payer,
        permanent_delegate_mint.pubkey(),
        decimals,
        payer.pubkey(),
    )?;
    assert_permanent_delegate(
        &rpc.account_data(permanent_delegate_mint.pubkey())?,
        permanent_delegate.pubkey(),
    )?;
    assert_state_value(
        &rpc,
        state.pubkey(),
        32,
        8,
        "marker after initialize_permanent_delegate",
    )?;

    let init_interest_bearing_signature = invoke_generated(
        &rpc,
        &payer,
        program_id,
        instruction(&artifact, "initialize_interest_bearing")?,
        pubkeys_for(&accounts, &[]),
        write_data(11, &[]),
        &known_signers,
    )?;
    let initialize_interest_bearing_mint_signature = initialize_mint(
        &rpc,
        &payer,
        interest_bearing_mint.pubkey(),
        decimals,
        payer.pubkey(),
    )?;
    assert_interest_bearing_config(
        &rpc.account_data(interest_bearing_mint.pubkey())?,
        interest_rate_authority.pubkey(),
        INTEREST_RATE_BASIS_POINTS,
    )?;
    assert_state_value(
        &rpc,
        state.pubkey(),
        32,
        9,
        "marker after initialize_interest_bearing",
    )?;

    let initialize_memo_transfer_mint_signature = initialize_mint(
        &rpc,
        &payer,
        memo_transfer_mint.pubkey(),
        decimals,
        payer.pubkey(),
    )?;
    let initialize_memo_transfer_account_signature = initialize_account(
        &rpc,
        &payer,
        memo_transfer_account.pubkey(),
        memo_transfer_mint.pubkey(),
        token_owner.pubkey(),
    )?;
    let enable_memo_transfer_signature = invoke_generated(
        &rpc,
        &payer,
        program_id,
        instruction(&artifact, "enable_memo_transfer")?,
        pubkeys_for(&accounts, &[]),
        write_data(12, &[]),
        &known_signers,
    )?;
    assert_memo_transfer(&rpc.account_data(memo_transfer_account.pubkey())?, true)?;
    assert_state_value(
        &rpc,
        state.pubkey(),
        32,
        10,
        "marker after enable_memo_transfer",
    )?;

    let init_transfer_hook_signature = invoke_generated(
        &rpc,
        &payer,
        program_id,
        instruction(&artifact, "initialize_transfer_hook")?,
        pubkeys_for(&accounts, &[]),
        write_data(13, &[]),
        &known_signers,
    )?;
    let initialize_transfer_hook_mint_signature = initialize_mint(
        &rpc,
        &payer,
        transfer_hook_mint.pubkey(),
        decimals,
        payer.pubkey(),
    )?;
    assert_transfer_hook_config(
        &rpc.account_data(transfer_hook_mint.pubkey())?,
        transfer_hook_authority.pubkey(),
        transfer_hook_program.pubkey(),
    )?;
    assert_state_value(
        &rpc,
        state.pubkey(),
        32,
        11,
        "marker after initialize_transfer_hook",
    )?;

    println!(
        "{}",
        json!({
            "programId": program_id.to_string(),
            "state": state.pubkey().to_string(),
            "payer": payer.pubkey().to_string(),
            "tokenOwner": token_owner.pubkey().to_string(),
            "withdrawWithheldAuthority": withdraw_withheld_authority.pubkey().to_string(),
            "transferFeeConfigAuthority": transfer_fee_config_authority.pubkey().to_string(),
            "mint": transfer_fee_mint.pubkey().to_string(),
            "metadataPointerMint": metadata_pointer_mint.pubkey().to_string(),
            "defaultStateMint": default_state_mint.pubkey().to_string(),
            "immutableOwnerMint": immutable_owner_mint.pubkey().to_string(),
            "immutableOwnerAccount": immutable_owner_account.pubkey().to_string(),
            "nonTransferableMint": non_transferable_mint.pubkey().to_string(),
            "permanentDelegateMint": permanent_delegate_mint.pubkey().to_string(),
            "interestBearingMint": interest_bearing_mint.pubkey().to_string(),
            "memoTransferMint": memo_transfer_mint.pubkey().to_string(),
            "memoTransferAccount": memo_transfer_account.pubkey().to_string(),
            "transferHookMint": transfer_hook_mint.pubkey().to_string(),
            "metadataPointerAuthority": metadata_pointer_authority.pubkey().to_string(),
            "metadataAddress": metadata_address.pubkey().to_string(),
            "permanentDelegate": permanent_delegate.pubkey().to_string(),
            "interestRateAuthority": interest_rate_authority.pubkey().to_string(),
            "transferHookAuthority": transfer_hook_authority.pubkey().to_string(),
            "transferHookProgram": transfer_hook_program.pubkey().to_string(),
            "ownerAta": owner_ata.to_string(),
            "recipientAta": recipient_ata.to_string(),
            "harvestRecipientAta": harvest_recipient_ata.to_string(),
            "feeReceiverAta": fee_receiver_ata.to_string(),
            "tokenProgram": token_2022_program_id().to_string(),
            "decimals": decimals,
            "initialSupply": initial_supply.to_string(),
            "transferAmount": transfer_amount.to_string(),
            "expectedFee": expected_fee.to_string(),
            "transferFeeBasisPoints": transfer_fee_basis_points.to_string(),
            "maximumFee": maximum_fee.to_string(),
            "nextBasisPoints": next_basis_points.to_string(),
            "nextMaximumFee": next_maximum_fee.to_string(),
            "interestRateBasisPoints": INTEREST_RATE_BASIS_POINTS.to_string(),
            "defaultAccountState": ACCOUNT_STATE_FROZEN_U64.to_string(),
            "ownerFinal": owner_account.amount.to_string(),
            "recipientFinal": recipient_account.amount.to_string(),
            "harvestRecipientFinal": harvest_recipient_account.amount.to_string(),
            "feeReceiverFinal": fee_receiver_account.amount.to_string(),
            "signatures": {
                "initFee": init_fee_signature,
                "initializeMint": initialize_mint_signature,
                "mintTo": mint_to_signature,
                "transfer": transfer_signature,
                "withdrawFromAccounts": withdraw_from_accounts_signature,
                "harvestTransfer": harvest_transfer_signature,
                "harvestToMint": harvest_to_mint_signature,
                "withdrawFromMint": withdraw_from_mint_signature,
                "setFee": set_fee_signature,
                "initNonTransferable": init_non_transferable_signature,
                "initializeNonTransferableMint": initialize_non_transferable_mint_signature,
                "initMetadataPointer": init_metadata_pointer_signature,
                "initializeMetadataPointerMint": initialize_metadata_pointer_mint_signature,
                "initDefaultAccountState": init_default_account_state_signature,
                "initializeDefaultStateMint": initialize_default_state_mint_signature,
                "initializeImmutableOwnerMint": initialize_immutable_owner_mint_signature,
                "initImmutableOwner": init_immutable_owner_signature,
                "initializeImmutableOwnerAccount": initialize_immutable_owner_account_signature,
                "initPermanentDelegate": init_permanent_delegate_signature,
                "initializePermanentDelegateMint": initialize_permanent_delegate_mint_signature,
                "initInterestBearing": init_interest_bearing_signature,
                "initializeInterestBearingMint": initialize_interest_bearing_mint_signature,
                "initializeMemoTransferMint": initialize_memo_transfer_mint_signature,
                "initializeMemoTransferAccount": initialize_memo_transfer_account_signature,
                "enableMemoTransfer": enable_memo_transfer_signature,
                "initTransferHook": init_transfer_hook_signature,
                "initializeTransferHookMint": initialize_transfer_hook_mint_signature,
            },
        })
    );

    Ok(())
}

fn load_artifact(path: PathBuf) -> Result<Artifact> {
    let text = fs::read_to_string(&path)
        .with_context(|| format!("failed to read `{}`", path.display()))?;
    serde_json::from_str(&text).with_context(|| format!("failed to parse `{}`", path.display()))
}

fn instruction<'a>(artifact: &'a Artifact, name: &str) -> Result<&'a ArtifactInstruction> {
    artifact
        .solana_instructions
        .iter()
        .find(|instruction| instruction.name == name)
        .with_context(|| format!("artifact missing instruction `{name}`"))
}

fn invoke_generated(
    rpc: &LiveRpc,
    payer: &Keypair,
    program_id: Address,
    artifact_instruction: &ArtifactInstruction,
    pubkeys: HashMap<String, Address>,
    data: Vec<u8>,
    known_signers: &[&Keypair],
) -> Result<String> {
    let accounts = artifact_instruction
        .accounts
        .iter()
        .map(|account| {
            let pubkey = pubkeys
                .get(&account.name)
                .copied()
                .with_context(|| format!("missing pubkey for account `{}`", account.name))?;
            Ok(AccountMeta {
                pubkey,
                is_signer: account.signer,
                is_writable: account.writable,
            })
        })
        .collect::<Result<Vec<_>>>()?;
    let instruction = Instruction {
        program_id,
        accounts,
        data,
    };
    let mut signers = vec![payer];
    for account in &artifact_instruction.accounts {
        if !account.signer {
            continue;
        }
        let pubkey = pubkeys
            .get(&account.name)
            .copied()
            .with_context(|| format!("missing signer pubkey for account `{}`", account.name))?;
        if pubkey == payer.pubkey() || signers.iter().any(|signer| signer.pubkey() == pubkey) {
            continue;
        }
        let signer = known_signers
            .iter()
            .copied()
            .find(|signer| signer.pubkey() == pubkey)
            .ok_or_else(|| {
                anyhow!(
                    "missing keypair for signer account `{}` ({pubkey})",
                    account.name
                )
            })?;
        signers.push(signer);
    }
    rpc.send_and_confirm(&[instruction], &signers)
        .with_context(|| format!("generated {} failed", artifact_instruction.name))
}

fn pubkeys_for(
    accounts: &GeneratedAccounts,
    overrides: &[(&str, Address)],
) -> HashMap<String, Address> {
    let mut pubkeys = HashMap::from([
        ("last_amount".to_string(), accounts.state),
        ("mint".to_string(), accounts.transfer_fee_mint),
        ("spl_token_2022".to_string(), token_2022_program_id()),
        ("source".to_string(), accounts.scratch_source),
        ("destination".to_string(), accounts.scratch_destination),
        ("authority".to_string(), accounts.token_owner),
        ("fee_receiver".to_string(), accounts.scratch_fee_receiver),
        (
            "withdraw_withheld_authority".to_string(),
            accounts.withdraw_withheld_authority,
        ),
        (
            "withheld_source".to_string(),
            accounts.scratch_withheld_source,
        ),
        (
            "transfer_fee_config_authority".to_string(),
            accounts.transfer_fee_config_authority,
        ),
        (
            "non_transferable_mint".to_string(),
            accounts.non_transferable_mint,
        ),
        (
            "metadata_pointer_mint".to_string(),
            accounts.metadata_pointer_mint,
        ),
        (
            "default_state_mint".to_string(),
            accounts.default_state_mint,
        ),
        (
            "immutable_owner_account".to_string(),
            accounts.immutable_owner_account,
        ),
        (
            "permanent_delegate_mint".to_string(),
            accounts.permanent_delegate_mint,
        ),
        (
            "interest_bearing_mint".to_string(),
            accounts.interest_bearing_mint,
        ),
        (
            "memo_transfer_account".to_string(),
            accounts.memo_transfer_account,
        ),
        (
            "transfer_hook_mint".to_string(),
            accounts.transfer_hook_mint,
        ),
        (
            "metadata_pointer_authority".to_string(),
            accounts.metadata_pointer_authority,
        ),
        ("metadata_address".to_string(), accounts.metadata_address),
        (
            "permanent_delegate".to_string(),
            accounts.permanent_delegate,
        ),
        (
            "interest_rate_authority".to_string(),
            accounts.interest_rate_authority,
        ),
        (
            "transfer_hook_authority".to_string(),
            accounts.transfer_hook_authority,
        ),
        (
            "transfer_hook_program".to_string(),
            accounts.transfer_hook_program,
        ),
    ]);
    for (name, pubkey) in overrides {
        pubkeys.insert((*name).to_string(), *pubkey);
    }
    pubkeys
}

fn write_data(tag: u8, values: &[u64]) -> Vec<u8> {
    let mut data = Vec::with_capacity(1 + values.len() * 8);
    data.push(tag);
    for value in values {
        data.extend_from_slice(&value.to_le_bytes());
    }
    data
}

fn assert_state_value(
    rpc: &LiveRpc,
    state: Address,
    offset: usize,
    expected: u64,
    label: &str,
) -> Result<()> {
    let data = rpc.account_data(state)?;
    assert_amount(label, read_u64_le_at(&data, offset)?, expected)
}

fn assert_amount(label: &str, actual: u64, expected: u64) -> Result<()> {
    ensure!(
        actual == expected,
        "{label} amount mismatch: expected {expected}, got {actual}"
    );
    Ok(())
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
