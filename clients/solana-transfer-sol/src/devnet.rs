//! Explicit opt-in Devnet transfer call path (blockheight / ambiguous-send state machine).

use std::path::Path;

use base64::{engine::general_purpose::STANDARD as B64, Engine as _};
use serde_json::json;
use solana_signer::Signer;

use crate::artifact::{verify_transfer_sol_artifact, VerifiedArtifact};
use crate::constants::TOCTOU_NOTE;
use crate::error::ClientError;
use crate::ix::{create_and_sign_transfer_tx, generate_ephemeral_keypair};
use crate::loader_v3::parse_pubkey;
use crate::receipt::{
    validate_transfer_receipt, ExpectedOuterTransferIx, LocalSignedTxFacts, SanitizedReceiptV1,
};
use crate::rpc::{ensure_funded, RpcBundle, SendOutcome};
use crate::util::sha256_hex;

#[derive(Debug)]
pub struct DevnetCallArgs<'a> {
    pub artifact_dir: &'a Path,
    pub program_id: &'a str,
    pub rpc_url: &'a str,
    pub lamports: u64,
    pub timeout_secs: u64,
    pub wall_deadline_secs: u64,
}

pub fn run_verify_artifacts(artifact_dir: &Path) -> Result<VerifiedArtifact, ClientError> {
    // Product surface: frozen sourceHash pin only (no override).
    verify_transfer_sol_artifact(artifact_dir)
}

pub fn run_devnet_call(args: DevnetCallArgs<'_>) -> Result<SanitizedReceiptV1, ClientError> {
    let verified = verify_transfer_sol_artifact(args.artifact_dir)?;
    let program_id = parse_pubkey(args.program_id)?;

    let rpc = RpcBundle::new(args.rpc_url, args.timeout_secs, args.wall_deadline_secs)?;
    let genesis = rpc.require_devnet_genesis()?;

    // Pre-send Loader V3 bind (point-in-time).
    let (_prog0, _pd0, bind0) = rpc.bind_program_to_local_so(&program_id, &verified.so_bytes)?;
    let pre_slot = bind0.last_modified_slot;
    let pre_prefix = bind0.onchain_prefix_sha256_hex.clone();
    let pre_auth = bind0.upgrade_authority.clone();

    let payer = generate_ephemeral_keypair();
    let recipient = generate_ephemeral_keypair();
    let payer_pk = payer.pubkey();
    let recipient_pk = recipient.pubkey();

    // Estimate the message fee, then complete the potentially slow faucet flow before
    // minting the final blockhash-bound signature. This avoids spending most of the
    // blockhash validity window waiting for an airdrop.
    let (fee_probe_hash, _) = rpc.get_latest_blockhash_with_commitment()?;
    let fee_probe_tx = create_and_sign_transfer_tx(
        &payer,
        &recipient_pk,
        &program_id,
        args.lamports,
        fee_probe_hash,
    );
    let fee_probe = rpc.estimate_fee(&fee_probe_tx)?;
    let initial_need = args
        .lamports
        .checked_add(fee_probe)
        .ok_or_else(|| ClientError::Internal("lamports+fee overflow".into()))?;
    ensure_funded(&rpc, &payer, initial_need)?;

    // Re-acquire a fresh blockhash after funding. If the exact final fee ever differs
    // and needs another airdrop, refresh again; never send a signature created before
    // a funding wait.
    let mut funding_refreshes = 0u8;
    let (tx, blockhash, last_valid_block_height, estimated_fee) = loop {
        let (candidate_hash, candidate_lvb) = rpc.get_latest_blockhash_with_commitment()?;
        let candidate_tx = create_and_sign_transfer_tx(
            &payer,
            &recipient_pk,
            &program_id,
            args.lamports,
            candidate_hash,
        );
        let candidate_fee = rpc.estimate_fee(&candidate_tx)?;
        let candidate_need = args
            .lamports
            .checked_add(candidate_fee)
            .ok_or_else(|| ClientError::Internal("lamports+fee overflow".into()))?;
        if rpc.get_balance(&payer_pk)? >= candidate_need {
            break (candidate_tx, candidate_hash, candidate_lvb, candidate_fee);
        }
        if funding_refreshes >= 2 {
            return Err(ClientError::DevnetConfig(
                "fee/funding did not stabilize after bounded blockhash refreshes".into(),
            ));
        }
        ensure_funded(&rpc, &payer, candidate_need)?;
        funding_refreshes += 1;
    };
    let local_sig = tx
        .signatures
        .first()
        .copied()
        .ok_or_else(|| ClientError::Internal("signed tx missing signature".into()))?;

    // Public facts on stderr after funding and before the sole transfer send.
    eprintln!("local_signature={local_sig}");
    eprintln!("recent_blockhash={blockhash}");
    eprintln!("lastValidBlockHeight={last_valid_block_height}");
    eprintln!("rpc_endpoint={}", rpc.display);
    eprintln!("genesis_hash={genesis}");

    // Re-bind immediately before send; reject slot/hash drift.
    let (_prog1, _pd1, bind1) = rpc.bind_program_to_local_so(&program_id, &verified.so_bytes)?;
    if bind1.last_modified_slot != pre_slot
        || bind1.onchain_prefix_sha256_hex != pre_prefix
        || bind1.upgrade_authority != pre_auth
    {
        return Err(ClientError::LoaderBind(format!(
            "pre-send ProgramData drift detected: slot {}→{} prefix {}→{} auth {:?}→{:?} ({})",
            pre_slot,
            bind1.last_modified_slot,
            pre_prefix,
            bind1.onchain_prefix_sha256_hex,
            pre_auth,
            bind1.upgrade_authority,
            TOCTOU_NOTE
        )));
    }
    let pre_send_height = rpc.get_block_height_confirmed()?;
    if pre_send_height > last_valid_block_height {
        return Err(ClientError::DevnetConfig(format!(
            "final blockhash expired before send (height {pre_send_height} > lastValidBlockHeight {last_valid_block_height}); transaction {local_sig} was not broadcast"
        )));
    }

    let send_outcome = rpc.send_once(&tx, &local_sig)?;
    let (sig, ambiguous_err) = match send_outcome {
        SendOutcome::Accepted { signature } => (signature, None),
        SendOutcome::Ambiguous {
            signature,
            send_error,
        } => (signature, Some(send_error)),
    };

    rpc.poll_until_confirmed_or_expired(&sig, last_valid_block_height, ambiguous_err.as_deref())?;

    // Post-confirm re-bind.
    let (_prog2, _pd2, bind2) = rpc.bind_program_to_local_so(&program_id, &verified.so_bytes)?;
    if bind2.last_modified_slot != pre_slot
        || bind2.onchain_prefix_sha256_hex != pre_prefix
        || bind2.upgrade_authority != pre_auth
    {
        return Err(ClientError::LoaderBind(format!(
            "post-confirm ProgramData drift vs pre-send bind: slot {}→{} prefix {}→{} ({})",
            pre_slot,
            bind2.last_modified_slot,
            pre_prefix,
            bind2.onchain_prefix_sha256_hex,
            TOCTOU_NOTE
        )));
    }

    let confirmed = rpc.fetch_confirmed_transaction(&sig.to_string())?;
    let expected =
        ExpectedOuterTransferIx::transfer_sol(program_id, payer_pk, recipient_pk, args.lamports);
    let ret = args.lamports.to_le_bytes();

    // Capture full signed transaction wire bytes (public).
    let signed_bytes = bincode::serialize(&tx)
        .map_err(|e| ClientError::Internal(format!("serialize signed tx: {e}")))?;
    let local_facts = local_facts_from_tx(&tx, &sig.to_string(), &signed_bytes)?;

    let receipt = validate_transfer_receipt(
        &confirmed,
        &expected,
        estimated_fee,
        &ret,
        &format!("devnet-confirmed genesis={genesis} rpc={}", rpc.display),
        bind2.upgrade_authority.clone(),
        bind2.last_modified_slot,
        &verified.so_sha256_hex,
        TOCTOU_NOTE,
        &local_facts,
    )?;

    // Ensure no private key material in receipt JSON (public keys only already).
    let _public_only = json!({
        "ephemeral_payer": payer_pk.to_string(),
        "ephemeral_recipient": recipient_pk.to_string(),
        "program_id": program_id.to_string(),
    });
    let _ = _public_only;

    Ok(receipt)
}

fn local_facts_from_tx(
    tx: &solana_transaction::Transaction,
    sig: &str,
    signed_bytes: &[u8],
) -> Result<LocalSignedTxFacts, ClientError> {
    let msg = &tx.message;
    let header = &msg.header;
    if msg.instructions.len() != 1 {
        return Err(ClientError::Internal(format!(
            "signed message must contain exactly one instruction, got {}",
            msg.instructions.len()
        )));
    }
    let compiled = &msg.instructions[0];
    Ok(LocalSignedTxFacts {
        signature_base58: sig.to_string(),
        recent_blockhash: msg.recent_blockhash.to_string(),
        num_required_signatures: header.num_required_signatures,
        num_readonly_signed_accounts: header.num_readonly_signed_accounts,
        num_readonly_unsigned_accounts: header.num_readonly_unsigned_accounts,
        account_keys: msg.account_keys.iter().map(|k| k.to_string()).collect(),
        program_id_index: compiled.program_id_index,
        account_indices: compiled.accounts.clone(),
        data: compiled.data.clone(),
        signed_tx_sha256_hex: sha256_hex(signed_bytes),
        signed_tx_base64: B64.encode(signed_bytes),
    })
}

pub fn print_verify_json(v: &VerifiedArtifact) -> Result<(), ClientError> {
    let out = json!({
        "ok": true,
        "command": "verify-artifacts",
        "artifactDir": v.dir.display().to_string(),
        "programName": v.manifest.artifact_program_name,
        "target": v.manifest.target,
        "codegenProfile": v.manifest.codegen_profile,
        "deployable": v.manifest.deployable,
        "sourceHash": v.manifest.source_hash,
        "semanticHash": v.manifest.semantic_hash,
        "planDigest": v.plan_digest_hex,
        "profileDigest": v.profile_digest_hex,
        "catalogDigest": v.catalog_digest_hex,
        "irDigest": v.ir_digest_hex,
        "outputSetDigest": v.manifest.output_set_digest,
        "soSha256": v.so_sha256_hex,
        "soPath": v.so_path.display().to_string(),
        "maturity": {
            "formal": false,
            "hermetic": false,
            "mainnet": false,
            "deploymentComplete": false,
            "note": "Offline OutputSet exact-closure + domain digests + ABI join only. ProofForge does not deploy."
        }
    });
    println!(
        "{}",
        serde_json::to_string_pretty(&out).map_err(|e| ClientError::Internal(e.to_string()))?
    );
    Ok(())
}

pub fn print_receipt_json(receipt: &SanitizedReceiptV1) -> Result<(), ClientError> {
    println!(
        "{}",
        serde_json::to_string_pretty(receipt).map_err(|e| ClientError::Internal(e.to_string()))?
    );
    Ok(())
}
