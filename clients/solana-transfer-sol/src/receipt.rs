//! Confirmed-transaction receipt validation (Json-encoding wire shape).

use base64::{engine::general_purpose::STANDARD as B64, Engine as _};
use serde::{Deserialize, Serialize};
use solana_pubkey::Pubkey;

use crate::constants::SANITIZED_RECEIPT_SCHEMA;
use crate::error::ClientError;
use crate::ix::system_transfer_ix_data;
use crate::loader_v3::system_program_id;

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ExpectedOuterTransferIx {
    pub program_id: Pubkey,
    pub accounts: [Pubkey; 3],
    pub data: [u8; 16],
}

impl ExpectedOuterTransferIx {
    pub fn transfer_sol(
        program_id: Pubkey,
        payer: Pubkey,
        recipient: Pubkey,
        lamports: u64,
    ) -> Self {
        let mut data = [0u8; 16];
        data[0..8].copy_from_slice(&0u64.to_le_bytes());
        data[8..16].copy_from_slice(&lamports.to_le_bytes());
        Self {
            program_id,
            accounts: [payer, recipient, system_program_id()],
            data,
        }
    }

    pub fn lamports(&self) -> u64 {
        u64::from_le_bytes(self.data[8..16].try_into().unwrap())
    }
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ConfirmedTransactionJson {
    pub slot: u64,
    pub transaction: EncodedTransactionWithMetaJson,
    #[serde(default)]
    pub block_time: Option<i64>,
    #[serde(default)]
    pub transaction_index: Option<u32>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct EncodedTransactionWithMetaJson {
    pub transaction: UiTransactionJson,
    #[serde(default)]
    pub meta: Option<UiTransactionStatusMetaJson>,
    #[serde(default)]
    pub version: Option<serde_json::Value>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UiTransactionJson {
    pub signatures: Vec<String>,
    pub message: UiRawMessageJson,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UiMessageHeaderJson {
    pub num_required_signatures: u8,
    pub num_readonly_signed_accounts: u8,
    pub num_readonly_unsigned_accounts: u8,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UiRawMessageJson {
    pub account_keys: Vec<String>,
    pub recent_blockhash: String,
    pub instructions: Vec<UiCompiledInstructionJson>,
    #[serde(default)]
    pub header: Option<UiMessageHeaderJson>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UiCompiledInstructionJson {
    pub program_id_index: u8,
    pub accounts: Vec<u8>,
    pub data: String,
    #[serde(default)]
    pub stack_height: Option<u32>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UiTransactionStatusMetaJson {
    #[serde(default)]
    pub err: Option<serde_json::Value>,
    pub fee: u64,
    pub pre_balances: Vec<u64>,
    pub post_balances: Vec<u64>,
    #[serde(default)]
    pub inner_instructions: Option<Vec<UiInnerInstructionsJson>>,
    #[serde(default)]
    pub log_messages: Option<Vec<String>>,
    #[serde(default)]
    pub return_data: Option<UiTransactionReturnDataJson>,
    #[serde(default)]
    pub compute_units_consumed: Option<u64>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UiInnerInstructionsJson {
    pub index: u8,
    pub instructions: Vec<UiCompiledInstructionJson>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UiTransactionReturnDataJson {
    pub program_id: String,
    pub data: (String, String),
}

/// Local signed message L1 facts for receipt join (no private keys).
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct LocalSignedTxFacts {
    pub signature_base58: String,
    pub recent_blockhash: String,
    pub num_required_signatures: u8,
    pub num_readonly_signed_accounts: u8,
    pub num_readonly_unsigned_accounts: u8,
    pub account_keys: Vec<String>,
    pub program_id_index: u8,
    pub account_indices: Vec<u8>,
    pub data: Vec<u8>,
    /// Full signed transaction bincode bytes SHA-256 (no private-key material in clear).
    pub signed_tx_sha256_hex: String,
    /// Full signed transaction bytes base64 (public wire form of the signed tx).
    pub signed_tx_base64: String,
}

/// Sanitized receipt fields (no secrets / no private keys).
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct SanitizedReceiptV1 {
    pub schema: String,
    pub signature: String,
    pub slot: u64,
    pub block_time: Option<i64>,
    pub confirmation_context: String,
    pub err: Option<String>,
    pub fee_lamports: u64,
    pub account_keys: Vec<String>,
    pub pre_balances: Vec<u64>,
    pub post_balances: Vec<u64>,
    pub outer_program_id: String,
    pub outer_account_keys: Vec<String>,
    pub outer_data_hex: String,
    pub outer_data_len: usize,
    pub outer_instruction_count: usize,
    pub inner_system_transfer_found: bool,
    pub inner_system_transfer_lamports: Option<u64>,
    pub log_messages: Vec<String>,
    pub return_data_program_id: Option<String>,
    pub return_data_hex: Option<String>,
    pub compute_units_consumed: Option<u64>,
    pub estimated_fee_lamports: u64,
    pub payer_index: usize,
    pub recipient_index: usize,
    pub payer_delta_lamports: i128,
    pub recipient_delta_lamports: i128,
    pub upgrade_authority_at_bind: Option<String>,
    pub programdata_slot_at_bind: u64,
    pub local_so_sha256_hex: String,
    pub toctou_note: String,
    pub signed_tx_sha256_hex: String,
    pub signed_tx_base64: String,
    pub recent_blockhash: String,
    pub message_header: UiMessageHeaderJson,
}

pub fn extract_outer_ix0(
    tx: &ConfirmedTransactionJson,
) -> Result<(Vec<String>, UiCompiledInstructionJson), ClientError> {
    let raw = &tx.transaction.transaction.message;
    let ix = raw
        .instructions
        .first()
        .cloned()
        .ok_or_else(|| ClientError::Receipt("no outer instructions".into()))?;
    Ok((raw.account_keys.clone(), ix))
}

pub fn check_signature_string(
    tx: &ConfirmedTransactionJson,
    expected_sig_base58: &str,
) -> Result<(), ClientError> {
    let actual = tx
        .transaction
        .transaction
        .signatures
        .first()
        .ok_or_else(|| ClientError::Receipt("no signatures".into()))?;
    if actual != expected_sig_base58 {
        return Err(ClientError::Receipt(format!(
            "signature mismatch: expected={expected_sig_base58} actual={actual}"
        )));
    }
    Ok(())
}

pub fn check_outer_transfer_ix(
    tx: &ConfirmedTransactionJson,
    expected: &ExpectedOuterTransferIx,
) -> Result<(), ClientError> {
    let (keys, ix) = extract_outer_ix0(tx)?;
    let prog = keys
        .get(ix.program_id_index as usize)
        .ok_or_else(|| ClientError::Receipt("program_id_index OOR".into()))?;
    let exp_prog = expected.program_id.to_string();
    if prog != &exp_prog {
        return Err(ClientError::Receipt(format!(
            "outer program mismatch: expected={exp_prog} actual={prog}"
        )));
    }
    let actual_accounts: Vec<String> = ix
        .accounts
        .iter()
        .map(|&i| {
            keys.get(i as usize)
                .cloned()
                .unwrap_or_else(|| format!("OOR:{i}"))
        })
        .collect();
    let expected_accounts: Vec<String> = expected.accounts.iter().map(|p| p.to_string()).collect();
    if actual_accounts != expected_accounts {
        return Err(ClientError::Receipt(format!(
            "outer accounts mismatch: expected={expected_accounts:?} actual={actual_accounts:?}"
        )));
    }
    let data = bs58::decode(&ix.data)
        .into_vec()
        .map_err(|e| ClientError::Receipt(format!("ix data base58: {e}")))?;
    if data.len() != 16 {
        return Err(ClientError::Receipt(format!(
            "outer data not 16 bytes: actual_len={}",
            data.len()
        )));
    }
    if data.as_slice() != expected.data.as_slice() {
        return Err(ClientError::Receipt(format!(
            "outer data mismatch: expected={} actual={}",
            hex::encode(expected.data),
            hex::encode(data)
        )));
    }
    Ok(())
}

pub fn check_balance_deltas(
    meta: &UiTransactionStatusMetaJson,
    expected_deltas: &[(usize, i128)],
) -> Result<(), ClientError> {
    if meta.pre_balances.len() != meta.post_balances.len() {
        return Err(ClientError::Receipt(format!(
            "balance len mismatch pre={} post={}",
            meta.pre_balances.len(),
            meta.post_balances.len()
        )));
    }
    for &(index, expected_delta) in expected_deltas {
        let pre = *meta
            .pre_balances
            .get(index)
            .ok_or_else(|| ClientError::Receipt(format!("pre_balances OOR {index}")))?;
        let post = *meta
            .post_balances
            .get(index)
            .ok_or_else(|| ClientError::Receipt(format!("post_balances OOR {index}")))?;
        let actual_delta = post as i128 - pre as i128;
        if actual_delta != expected_delta {
            return Err(ClientError::Receipt(format!(
                "balance delta mismatch index={index} expected={expected_delta} actual={actual_delta}"
            )));
        }
    }
    Ok(())
}

pub fn check_inner_system_transfer(
    meta: &UiTransactionStatusMetaJson,
    outer_ix_index: u8,
    expected_lamports: u64,
    account_keys: &[String],
    payer: &str,
    recipient: &str,
) -> Result<(), ClientError> {
    let inners = meta
        .inner_instructions
        .as_ref()
        .ok_or_else(|| ClientError::Receipt("missing inner_instructions".into()))?;
    if inners.len() != 1 {
        return Err(ClientError::Receipt(format!(
            "inner_instructions must contain exactly one group, got {}",
            inners.len()
        )));
    }
    let group = &inners[0];
    if group.index != outer_ix_index {
        return Err(ClientError::Receipt(format!(
            "inner group index must be {outer_ix_index}, got {}",
            group.index
        )));
    }
    if group.instructions.len() != 1 {
        return Err(ClientError::Receipt(format!(
            "inner group must contain exactly one System transfer, got {} instructions",
            group.instructions.len()
        )));
    }

    let c = &group.instructions[0];
    let prog = account_keys
        .get(c.program_id_index as usize)
        .ok_or_else(|| ClientError::Receipt("inner program_id_index OOR".into()))?;
    let sys = system_program_id().to_string();
    if prog != &sys {
        return Err(ClientError::Receipt(format!(
            "inner program must be System: actual={prog} expected={sys}"
        )));
    }
    let data = bs58::decode(&c.data)
        .into_vec()
        .map_err(|e| ClientError::Receipt(format!("inner data: {e}")))?;
    let want = system_transfer_ix_data(expected_lamports);
    if data.as_slice() != want.as_slice() {
        return Err(ClientError::Receipt(format!(
            "inner System data mismatch: actual={} expected={}",
            hex::encode(data),
            hex::encode(want)
        )));
    }
    if c.accounts.len() != 2 {
        return Err(ClientError::Receipt(format!(
            "inner System accounts must be exactly [payer,recipient], got len={}",
            c.accounts.len()
        )));
    }
    let a0 = account_keys
        .get(c.accounts[0] as usize)
        .ok_or_else(|| ClientError::Receipt("inner payer index OOR".into()))?;
    let a1 = account_keys
        .get(c.accounts[1] as usize)
        .ok_or_else(|| ClientError::Receipt("inner recipient index OOR".into()))?;
    if a0 != payer || a1 != recipient {
        return Err(ClientError::Receipt(format!(
            "inner System accounts mismatch: actual=[{a0},{a1}] expected=[{payer},{recipient}]"
        )));
    }
    Ok(())
}

pub fn check_return_data(
    meta: &UiTransactionStatusMetaJson,
    expected_program_id: &Pubkey,
    expected_data: &[u8],
) -> Result<(), ClientError> {
    let rd = meta
        .return_data
        .as_ref()
        .ok_or_else(|| ClientError::Receipt("missing return_data".into()))?;
    if rd.program_id != expected_program_id.to_string() {
        return Err(ClientError::Receipt(format!(
            "return_data program mismatch: expected={} actual={}",
            expected_program_id, rd.program_id
        )));
    }
    if rd.data.1 != "base64" {
        return Err(ClientError::Receipt(format!(
            "return_data encoding must be base64, got {}",
            rd.data.1
        )));
    }
    let actual = B64
        .decode(rd.data.0.as_bytes())
        .map_err(|e| ClientError::Receipt(format!("return_data base64: {e}")))?;
    if actual.as_slice() != expected_data {
        return Err(ClientError::Receipt(format!(
            "return_data mismatch: expected={} actual={}",
            hex::encode(expected_data),
            hex::encode(actual)
        )));
    }
    Ok(())
}

/// Compare RPC message to local signed L1 facts (signature, blockhash, header, keys, ix).
pub fn check_local_signed_l1_facts(
    tx: &ConfirmedTransactionJson,
    local: &LocalSignedTxFacts,
) -> Result<(), ClientError> {
    check_signature_string(tx, &local.signature_base58)?;
    let msg = &tx.transaction.transaction.message;
    if msg.recent_blockhash != local.recent_blockhash {
        return Err(ClientError::Receipt(format!(
            "recentBlockhash mismatch: rpc={} local={}",
            msg.recent_blockhash, local.recent_blockhash
        )));
    }
    let header = msg
        .header
        .as_ref()
        .ok_or_else(|| ClientError::Receipt("message header required for L1 join".into()))?;
    if header.num_required_signatures != local.num_required_signatures
        || header.num_readonly_signed_accounts != local.num_readonly_signed_accounts
        || header.num_readonly_unsigned_accounts != local.num_readonly_unsigned_accounts
    {
        return Err(ClientError::Receipt(format!(
            "message header mismatch: rpc=({},{},{}) local=({},{},{})",
            header.num_required_signatures,
            header.num_readonly_signed_accounts,
            header.num_readonly_unsigned_accounts,
            local.num_required_signatures,
            local.num_readonly_signed_accounts,
            local.num_readonly_unsigned_accounts
        )));
    }
    if msg.account_keys != local.account_keys {
        return Err(ClientError::Receipt(format!(
            "accountKeys order mismatch: rpc={:?} local={:?}",
            msg.account_keys, local.account_keys
        )));
    }
    if msg.instructions.len() != 1 {
        return Err(ClientError::Receipt(format!(
            "outer instructions must be exactly 1, got {}",
            msg.instructions.len()
        )));
    }
    let ix = &msg.instructions[0];
    if ix.program_id_index != local.program_id_index {
        return Err(ClientError::Receipt(format!(
            "outer program_id_index mismatch: rpc={} local={}",
            ix.program_id_index, local.program_id_index
        )));
    }
    if ix.accounts != local.account_indices {
        return Err(ClientError::Receipt(format!(
            "outer account indices mismatch: rpc={:?} local={:?}",
            ix.accounts, local.account_indices
        )));
    }
    let data = bs58::decode(&ix.data)
        .into_vec()
        .map_err(|e| ClientError::Receipt(format!("outer data base58: {e}")))?;
    if data != local.data {
        return Err(ClientError::Receipt(format!(
            "outer data mismatch vs local signed: rpc={} local={}",
            hex::encode(data),
            hex::encode(&local.data)
        )));
    }
    Ok(())
}

pub fn check_log_program_success(
    meta: &UiTransactionStatusMetaJson,
    program_id: &Pubkey,
) -> Result<(), ClientError> {
    let logs = meta
        .log_messages
        .as_ref()
        .ok_or_else(|| ClientError::Receipt("log_messages absent".into()))?;
    let needle = format!("Program {program_id} success");
    if logs.iter().any(|l| l.contains(&needle)) {
        Ok(())
    } else {
        Err(ClientError::Receipt(format!(
            "missing log evidence: {needle}"
        )))
    }
}

#[allow(clippy::too_many_arguments)]
pub fn validate_transfer_receipt(
    tx: &ConfirmedTransactionJson,
    expected_outer: &ExpectedOuterTransferIx,
    estimated_fee: u64,
    expected_return_data: &[u8],
    confirmation_context: &str,
    upgrade_authority_at_bind: Option<String>,
    programdata_slot_at_bind: u64,
    local_so_sha256_hex: &str,
    toctou_note: &str,
    local: &LocalSignedTxFacts,
) -> Result<SanitizedReceiptV1, ClientError> {
    let meta = tx
        .transaction
        .meta
        .as_ref()
        .ok_or_else(|| ClientError::Receipt("missing meta".into()))?;
    if meta.err.is_some() {
        return Err(ClientError::Receipt(format!(
            "transaction failed: {:?}",
            meta.err
        )));
    }
    check_local_signed_l1_facts(tx, local)?;
    check_outer_transfer_ix(tx, expected_outer)?;

    let (keys, ix) = extract_outer_ix0(tx)?;
    let payer_s = expected_outer.accounts[0].to_string();
    let recipient_s = expected_outer.accounts[1].to_string();
    let payer_index = keys
        .iter()
        .position(|k| k == &payer_s)
        .ok_or_else(|| ClientError::Receipt("payer not in account_keys".into()))?;
    if payer_index != 0 {
        return Err(ClientError::Receipt(format!(
            "payer must be account_keys[0] (fee payer), found at {payer_index}"
        )));
    }
    let recipient_index = keys
        .iter()
        .position(|k| k == &recipient_s)
        .ok_or_else(|| ClientError::Receipt("recipient not in account_keys".into()))?;

    let lamports = expected_outer.lamports() as i128;
    let actual_fee = meta.fee as i128;
    // `getFeeForMessage` is an estimate from a point-in-time RPC view. Preserve it
    // in the receipt, but verify the landed balance equation against observed meta.fee.
    check_balance_deltas(
        meta,
        &[
            (payer_index, -(lamports + actual_fee)),
            (recipient_index, lamports),
        ],
    )?;
    check_inner_system_transfer(
        meta,
        0,
        expected_outer.lamports(),
        &keys,
        &payer_s,
        &recipient_s,
    )?;
    check_log_program_success(meta, &expected_outer.program_id)?;
    check_return_data(meta, &expected_outer.program_id, expected_return_data)?;

    let outer_program = keys
        .get(ix.program_id_index as usize)
        .cloned()
        .unwrap_or_default();
    let outer_accounts: Vec<String> = ix
        .accounts
        .iter()
        .map(|&i| keys.get(i as usize).cloned().unwrap_or_default())
        .collect();
    let outer_data = bs58::decode(&ix.data)
        .into_vec()
        .map_err(|e| ClientError::Receipt(e.to_string()))?;

    // `check_inner_system_transfer` already proved exact sole-inner cardinality,
    // program, accounts, codec, and amount.
    let inner_found = true;
    let inner_lamports = Some(expected_outer.lamports());

    let logs = meta.log_messages.clone().unwrap_or_default();
    let (rd_prog, rd_hex) = match &meta.return_data {
        Some(rd) => {
            let bytes = B64.decode(rd.data.0.as_bytes()).unwrap_or_default();
            (Some(rd.program_id.clone()), Some(hex::encode(bytes)))
        }
        None => (None, None),
    };

    let payer_delta =
        meta.post_balances[payer_index] as i128 - meta.pre_balances[payer_index] as i128;
    let recipient_delta =
        meta.post_balances[recipient_index] as i128 - meta.pre_balances[recipient_index] as i128;

    let header = tx
        .transaction
        .transaction
        .message
        .header
        .clone()
        .ok_or_else(|| ClientError::Receipt("header required".into()))?;

    Ok(SanitizedReceiptV1 {
        schema: SANITIZED_RECEIPT_SCHEMA.to_string(),
        signature: local.signature_base58.clone(),
        slot: tx.slot,
        block_time: tx.block_time,
        confirmation_context: confirmation_context.to_string(),
        err: None,
        fee_lamports: meta.fee,
        account_keys: keys,
        pre_balances: meta.pre_balances.clone(),
        post_balances: meta.post_balances.clone(),
        outer_program_id: outer_program,
        outer_account_keys: outer_accounts,
        outer_data_hex: hex::encode(&outer_data),
        outer_data_len: outer_data.len(),
        outer_instruction_count: 1,
        inner_system_transfer_found: inner_found,
        inner_system_transfer_lamports: inner_lamports,
        log_messages: logs,
        return_data_program_id: rd_prog,
        return_data_hex: rd_hex,
        compute_units_consumed: meta.compute_units_consumed,
        estimated_fee_lamports: estimated_fee,
        payer_index,
        recipient_index,
        payer_delta_lamports: payer_delta,
        recipient_delta_lamports: recipient_delta,
        upgrade_authority_at_bind,
        programdata_slot_at_bind,
        local_so_sha256_hex: local_so_sha256_hex.to_string(),
        toctou_note: toctou_note.to_string(),
        signed_tx_sha256_hex: local.signed_tx_sha256_hex.clone(),
        signed_tx_base64: local.signed_tx_base64.clone(),
        recent_blockhash: local.recent_blockhash.clone(),
        message_header: header,
    })
}

/// Build a Json-encoded confirmed transaction fixture for offline tests.
#[allow(clippy::too_many_arguments)]
pub fn synth_confirmed_transfer_tx(
    signature: &str,
    slot: u64,
    program_id: Pubkey,
    payer: Pubkey,
    recipient: Pubkey,
    lamports: u64,
    fee: u64,
    payer_pre: u64,
    recipient_pre: u64,
    return_data: &[u8],
) -> ConfirmedTransactionJson {
    let system = system_program_id();
    let account_keys = vec![
        payer.to_string(),
        recipient.to_string(),
        program_id.to_string(),
        system.to_string(),
    ];
    let outer_data = {
        let mut d = [0u8; 16];
        d[0..8].copy_from_slice(&0u64.to_le_bytes());
        d[8..16].copy_from_slice(&lamports.to_le_bytes());
        bs58::encode(d).into_string()
    };
    let outer_ix = UiCompiledInstructionJson {
        program_id_index: 2,
        accounts: vec![0, 1, 3],
        data: outer_data,
        stack_height: Some(1),
    };
    let inner_data = bs58::encode(system_transfer_ix_data(lamports)).into_string();
    let inner_ix = UiCompiledInstructionJson {
        program_id_index: 3,
        accounts: vec![0, 1],
        data: inner_data,
        stack_height: Some(2),
    };
    ConfirmedTransactionJson {
        slot,
        block_time: Some(1_700_000_000),
        transaction_index: Some(0),
        transaction: EncodedTransactionWithMetaJson {
            transaction: UiTransactionJson {
                signatures: vec![signature.to_string()],
                message: UiRawMessageJson {
                    account_keys: account_keys.clone(),
                    recent_blockhash: "11111111111111111111111111111111".to_string(),
                    instructions: vec![outer_ix],
                    header: Some(UiMessageHeaderJson {
                        num_required_signatures: 1,
                        num_readonly_signed_accounts: 0,
                        num_readonly_unsigned_accounts: 2,
                    }),
                },
            },
            meta: Some(UiTransactionStatusMetaJson {
                err: None,
                fee,
                pre_balances: vec![payer_pre, recipient_pre, 1, 1],
                post_balances: vec![payer_pre - lamports - fee, recipient_pre + lamports, 1, 1],
                inner_instructions: Some(vec![UiInnerInstructionsJson {
                    index: 0,
                    instructions: vec![inner_ix],
                }]),
                log_messages: Some(vec![
                    format!("Program {program_id} invoke [1]"),
                    format!("Program {system} invoke [2]"),
                    format!("Program {system} success"),
                    format!("Program {program_id} success"),
                ]),
                return_data: Some(UiTransactionReturnDataJson {
                    program_id: program_id.to_string(),
                    data: (B64.encode(return_data), "base64".to_string()),
                }),
                compute_units_consumed: Some(12_345),
            }),
            version: None,
        },
    }
}

/// Build local L1 facts matching [`synth_confirmed_transfer_tx`].
pub fn synth_local_facts(
    signature: &str,
    program_id: Pubkey,
    payer: Pubkey,
    recipient: Pubkey,
    lamports: u64,
) -> LocalSignedTxFacts {
    let mut data = [0u8; 16];
    data[0..8].copy_from_slice(&0u64.to_le_bytes());
    data[8..16].copy_from_slice(&lamports.to_le_bytes());
    let account_keys = vec![
        payer.to_string(),
        recipient.to_string(),
        program_id.to_string(),
        system_program_id().to_string(),
    ];
    LocalSignedTxFacts {
        signature_base58: signature.to_string(),
        recent_blockhash: "11111111111111111111111111111111".to_string(),
        num_required_signatures: 1,
        num_readonly_signed_accounts: 0,
        num_readonly_unsigned_accounts: 2,
        account_keys,
        program_id_index: 2,
        account_indices: vec![0, 1, 3],
        data: data.to_vec(),
        signed_tx_sha256_hex: crate::util::sha256_hex(b"synth-signed-tx"),
        signed_tx_base64: B64.encode(b"synth-signed-tx"),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::constants::TOCTOU_NOTE;

    fn validate_ok(
        tx: &ConfirmedTransactionJson,
        expected: &ExpectedOuterTransferIx,
        fee: u64,
        ret: &[u8],
        local: &LocalSignedTxFacts,
    ) -> Result<SanitizedReceiptV1, ClientError> {
        validate_transfer_receipt(
            tx,
            expected,
            fee,
            ret,
            "offline-fixture",
            None,
            9,
            "deadbeef",
            TOCTOU_NOTE,
            local,
        )
    }

    #[test]
    fn receipt_positive_and_json_roundtrip() {
        let program_id = Pubkey::new_unique();
        let payer = Pubkey::new_unique();
        let recipient = Pubkey::new_unique();
        let lamports = 2_500_000u64;
        let fee = 5000u64;
        let sig = "SyntheticSig111111111111111111111111111111111111111111111111111";
        let ret = lamports.to_le_bytes();
        let tx = synth_confirmed_transfer_tx(
            sig, 12345, program_id, payer, recipient, lamports, fee, 50_000_000, 1_000_000, &ret,
        );
        let expected =
            ExpectedOuterTransferIx::transfer_sol(program_id, payer, recipient, lamports);
        let local = synth_local_facts(sig, program_id, payer, recipient, lamports);
        let receipt = validate_ok(&tx, &expected, fee, &ret, &local).expect("validate");
        assert_eq!(receipt.schema, SANITIZED_RECEIPT_SCHEMA);
        assert!(receipt.inner_system_transfer_found);
        assert_eq!(receipt.inner_system_transfer_lamports, Some(lamports));
        assert_eq!(receipt.payer_delta_lamports, -((lamports + fee) as i128));
        assert_eq!(receipt.recipient_delta_lamports, lamports as i128);
        assert_eq!(receipt.payer_index, 0);
        let json = serde_json::to_string(&receipt).unwrap();
        assert!(!json.contains("secret"));
        assert!(!json.contains("private"));
        let back: SanitizedReceiptV1 = serde_json::from_str(&json).unwrap();
        assert_eq!(back.signature, sig);
    }

    #[test]
    fn receipt_rejects_outer_data_len() {
        let program_id = Pubkey::new_unique();
        let payer = Pubkey::new_unique();
        let recipient = Pubkey::new_unique();
        let mut tx = synth_confirmed_transfer_tx(
            "sig",
            1,
            program_id,
            payer,
            recipient,
            100,
            5000,
            1_000_000,
            0,
            &100u64.to_le_bytes(),
        );
        tx.transaction.transaction.message.instructions[0].data =
            bs58::encode([0u8; 8]).into_string();
        let expected = ExpectedOuterTransferIx::transfer_sol(program_id, payer, recipient, 100);
        let err = check_outer_transfer_ix(&tx, &expected).unwrap_err();
        assert!(err.to_string().contains("not 16 bytes"));
    }

    #[test]
    fn receipt_uses_observed_fee_and_retains_estimate() {
        let program_id = Pubkey::new_unique();
        let payer = Pubkey::new_unique();
        let recipient = Pubkey::new_unique();
        let ret = 100u64.to_le_bytes();
        let tx = synth_confirmed_transfer_tx(
            "sig", 1, program_id, payer, recipient, 100, 5000, 1_000_000, 0, &ret,
        );
        let expected = ExpectedOuterTransferIx::transfer_sol(program_id, payer, recipient, 100);
        let local = synth_local_facts("sig", program_id, payer, recipient, 100);
        let receipt = validate_ok(&tx, &expected, 1, &ret, &local).unwrap();
        assert_eq!(receipt.fee_lamports, 5000);
        assert_eq!(receipt.estimated_fee_lamports, 1);
        assert_eq!(receipt.payer_delta_lamports, -5100);
    }

    #[test]
    fn receipt_rejects_balance_delta() {
        let program_id = Pubkey::new_unique();
        let payer = Pubkey::new_unique();
        let recipient = Pubkey::new_unique();
        let mut tx = synth_confirmed_transfer_tx(
            "sig",
            1,
            program_id,
            payer,
            recipient,
            100,
            5000,
            1_000_000,
            0,
            &100u64.to_le_bytes(),
        );
        tx.transaction.meta.as_mut().unwrap().post_balances[1] = 0;
        let expected = ExpectedOuterTransferIx::transfer_sol(program_id, payer, recipient, 100);
        let local = synth_local_facts("sig", program_id, payer, recipient, 100);
        let err = validate_ok(&tx, &expected, 5000, &100u64.to_le_bytes(), &local).unwrap_err();
        assert!(err.to_string().contains("balance delta"));
    }

    #[test]
    fn receipt_rejects_return_data() {
        let program_id = Pubkey::new_unique();
        let payer = Pubkey::new_unique();
        let recipient = Pubkey::new_unique();
        let tx = synth_confirmed_transfer_tx(
            "sig",
            1,
            program_id,
            payer,
            recipient,
            100,
            5000,
            1_000_000,
            0,
            &100u64.to_le_bytes(),
        );
        let expected = ExpectedOuterTransferIx::transfer_sol(program_id, payer, recipient, 100);
        let local = synth_local_facts("sig", program_id, payer, recipient, 100);
        let err = validate_ok(&tx, &expected, 5000, &999u64.to_le_bytes(), &local).unwrap_err();
        assert!(err.to_string().contains("return_data"));
    }

    #[test]
    fn receipt_rejects_inner_missing() {
        let program_id = Pubkey::new_unique();
        let payer = Pubkey::new_unique();
        let recipient = Pubkey::new_unique();
        let mut tx = synth_confirmed_transfer_tx(
            "sig",
            1,
            program_id,
            payer,
            recipient,
            100,
            5000,
            1_000_000,
            0,
            &100u64.to_le_bytes(),
        );
        tx.transaction.meta.as_mut().unwrap().inner_instructions = Some(vec![]);
        let expected = ExpectedOuterTransferIx::transfer_sol(program_id, payer, recipient, 100);
        let local = synth_local_facts("sig", program_id, payer, recipient, 100);
        let err = validate_ok(&tx, &expected, 5000, &100u64.to_le_bytes(), &local).unwrap_err();
        assert!(err.to_string().contains("inner"));
    }

    #[test]
    fn receipt_rejects_extra_inner_instruction() {
        let program_id = Pubkey::new_unique();
        let payer = Pubkey::new_unique();
        let recipient = Pubkey::new_unique();
        let ret = 100u64.to_le_bytes();
        let mut tx = synth_confirmed_transfer_tx(
            "sig", 1, program_id, payer, recipient, 100, 5000, 1_000_000, 0, &ret,
        );
        let duplicate = tx
            .transaction
            .meta
            .as_ref()
            .unwrap()
            .inner_instructions
            .as_ref()
            .unwrap()[0]
            .instructions[0]
            .clone();
        tx.transaction
            .meta
            .as_mut()
            .unwrap()
            .inner_instructions
            .as_mut()
            .unwrap()[0]
            .instructions
            .push(duplicate);
        let expected = ExpectedOuterTransferIx::transfer_sol(program_id, payer, recipient, 100);
        let local = synth_local_facts("sig", program_id, payer, recipient, 100);
        let err = validate_ok(&tx, &expected, 5000, &ret, &local).unwrap_err();
        assert!(err.to_string().contains("exactly one System transfer"));
    }

    #[test]
    fn receipt_rejects_blockhash_mismatch() {
        let program_id = Pubkey::new_unique();
        let payer = Pubkey::new_unique();
        let recipient = Pubkey::new_unique();
        let tx = synth_confirmed_transfer_tx(
            "sig",
            1,
            program_id,
            payer,
            recipient,
            100,
            5000,
            1_000_000,
            0,
            &100u64.to_le_bytes(),
        );
        let expected = ExpectedOuterTransferIx::transfer_sol(program_id, payer, recipient, 100);
        let mut local = synth_local_facts("sig", program_id, payer, recipient, 100);
        local.recent_blockhash = "22222222222222222222222222222222".into();
        let err = validate_ok(&tx, &expected, 5000, &100u64.to_le_bytes(), &local).unwrap_err();
        assert!(err.to_string().contains("recentBlockhash"));
    }

    #[test]
    fn receipt_rejects_inner_accounts_order() {
        let program_id = Pubkey::new_unique();
        let payer = Pubkey::new_unique();
        let recipient = Pubkey::new_unique();
        let mut tx = synth_confirmed_transfer_tx(
            "sig",
            1,
            program_id,
            payer,
            recipient,
            100,
            5000,
            1_000_000,
            0,
            &100u64.to_le_bytes(),
        );
        // Swap payer/recipient in inner accounts.
        tx.transaction
            .meta
            .as_mut()
            .unwrap()
            .inner_instructions
            .as_mut()
            .unwrap()[0]
            .instructions[0]
            .accounts = vec![1, 0];
        let expected = ExpectedOuterTransferIx::transfer_sol(program_id, payer, recipient, 100);
        let local = synth_local_facts("sig", program_id, payer, recipient, 100);
        let err = validate_ok(&tx, &expected, 5000, &100u64.to_le_bytes(), &local).unwrap_err();
        assert!(err.to_string().contains("inner System accounts"));
    }
}
