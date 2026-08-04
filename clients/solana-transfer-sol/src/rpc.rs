//! RPC helpers with redacted endpoints, blockheight poll, and one-shot send.

use std::str::FromStr;
use std::thread;
use std::time::{Duration, Instant};

use base64::{engine::general_purpose::STANDARD as B64, Engine as _};
use serde_json::{json, Value};
use solana_commitment_config::{CommitmentConfig, CommitmentLevel};
use solana_hash::Hash;
use solana_keypair::Keypair;
use solana_pubkey::Pubkey;
use solana_rpc_client::rpc_client::RpcClient;
use solana_rpc_client_api::config::RpcSendTransactionConfig;
use solana_signature::Signature;
use solana_signer::Signer;
use solana_transaction::Transaction;

use crate::constants::MAX_AIRDROP_LAMPORTS;
use crate::error::ClientError;
use crate::loader_v3::{AccountSnapshot, ElfBindResult, ProgramAccountDecode, ProgramDataDecode};
use crate::receipt::ConfirmedTransactionJson;
use crate::util::display_endpoint;

pub struct RpcBundle {
    /// Private full URL (may contain tokens). Never log this.
    url: String,
    /// Public redacted display form only.
    pub display: String,
    pub timeout_secs: u64,
    pub wall_deadline_secs: u64,
    pub client: RpcClient,
    http: reqwest::blocking::Client,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum PollDecision {
    Confirmed,
    OnChainError,
    ObservedUnconfirmed,
    CleanExpiry,
    Continue,
}

fn classify_poll_observation(
    status_present: bool,
    status_confirmed: bool,
    status_failed: bool,
    block_height: u64,
    last_valid_block_height: u64,
) -> PollDecision {
    if status_failed {
        PollDecision::OnChainError
    } else if status_confirmed {
        PollDecision::Confirmed
    } else if status_present {
        // A present Processed status is evidence that the transaction landed on
        // some observed fork. Crossing LVBH cannot turn that into clean expiry.
        PollDecision::ObservedUnconfirmed
    } else if block_height > last_valid_block_height {
        PollDecision::CleanExpiry
    } else {
        PollDecision::Continue
    }
}

impl RpcBundle {
    pub fn new(url: &str, timeout_secs: u64, wall_deadline_secs: u64) -> Result<Self, ClientError> {
        let display = display_endpoint(url);
        let http = reqwest::blocking::Client::builder()
            .timeout(Duration::from_secs(timeout_secs))
            .build()
            .map_err(|e| ClientError::rpc(&display, format!("http client build: {e}")))?;
        let client = RpcClient::new_with_timeout_and_commitment(
            url.to_string(),
            Duration::from_secs(timeout_secs),
            CommitmentConfig::confirmed(),
        );
        Ok(Self {
            url: url.to_string(),
            display,
            timeout_secs,
            wall_deadline_secs,
            client,
            http,
        })
    }

    fn redact_message(&self, message: impl Into<String>) -> String {
        let mut redacted = message.into().replace(&self.url, &self.display);
        // Error libraries may normalize a bare host URL by appending `/` or
        // canonicalizing escapes. Cover the parsed spelling as well as the raw input.
        if let Ok(parsed) = url::Url::parse(&self.url) {
            redacted = redacted.replace(parsed.as_str(), &self.display);
        }
        redacted
    }

    fn rpc_err(&self, message: impl Into<String>) -> ClientError {
        ClientError::rpc(&self.display, self.redact_message(message))
    }

    fn rpc_call(&self, method: &str, params: Value) -> Result<Value, ClientError> {
        let body = json!({
            "jsonrpc": "2.0",
            "id": 1,
            "method": method,
            "params": params,
        });
        let resp: Value = self
            .http
            .post(&self.url)
            .json(&body)
            .send()
            .map_err(|e| self.rpc_err(format!("http send {method}: {}", e.without_url())))?
            .error_for_status()
            .map_err(|e| self.rpc_err(format!("http status {method}: {}", e.without_url())))?
            .json()
            .map_err(|e| self.rpc_err(format!("http json {method}: {}", e.without_url())))?;
        if let Some(err) = resp.get("error") {
            return Err(self.rpc_err(format!("rpc error {method}: {err}")));
        }
        resp.get("result")
            .cloned()
            .ok_or_else(|| self.rpc_err(format!("missing result for {method}")))
    }

    pub fn require_devnet_genesis(&self) -> Result<String, ClientError> {
        use crate::constants::DEVNET_GENESIS_HASH_BASE58;
        let result = self.rpc_call("getGenesisHash", json!([]))?;
        let h = result
            .as_str()
            .ok_or_else(|| self.rpc_err("genesis hash not string"))?
            .to_string();
        if h != DEVNET_GENESIS_HASH_BASE58 {
            return Err(ClientError::DevnetConfig(format!(
                "genesis hash mismatch for endpoint {}: got {h}, expected Devnet {DEVNET_GENESIS_HASH_BASE58}",
                self.display
            )));
        }
        Ok(h)
    }

    pub fn fetch_account_confirmed(&self, pubkey: &Pubkey) -> Result<AccountSnapshot, ClientError> {
        let result = self.rpc_call(
            "getAccountInfo",
            json!([
                pubkey.to_string(),
                { "encoding": "base64", "commitment": "confirmed" }
            ]),
        )?;
        let value = result
            .get("value")
            .ok_or_else(|| self.rpc_err("account value missing"))?;
        if value.is_null() {
            return Err(self.rpc_err(format!("account not found: {pubkey}")));
        }
        let lamports = value["lamports"]
            .as_u64()
            .ok_or_else(|| self.rpc_err("lamports"))?;
        let owner = Pubkey::from_str(
            value["owner"]
                .as_str()
                .ok_or_else(|| self.rpc_err("owner missing"))?,
        )
        .map_err(|e| self.rpc_err(format!("owner parse: {e}")))?;
        let executable = value["executable"]
            .as_bool()
            .ok_or_else(|| self.rpc_err("executable"))?;
        let rent_epoch = value["rentEpoch"].as_u64().unwrap_or(0);
        let data_arr = value["data"]
            .as_array()
            .ok_or_else(|| self.rpc_err("data array"))?;
        let b64 = data_arr
            .first()
            .and_then(|v| v.as_str())
            .ok_or_else(|| self.rpc_err("data b64"))?;
        let data = B64
            .decode(b64)
            .map_err(|e| self.rpc_err(format!("account data b64: {e}")))?;
        Ok(AccountSnapshot {
            lamports,
            data,
            owner,
            executable,
            rent_epoch,
        })
    }

    pub fn bind_program_to_local_so(
        &self,
        program_id: &Pubkey,
        local_so: &[u8],
    ) -> Result<(ProgramAccountDecode, ProgramDataDecode, ElfBindResult), ClientError> {
        let prog_acc = self.fetch_account_confirmed(program_id)?;
        let prog = crate::loader_v3::decode_loader_v3_program_account(program_id, &prog_acc)?;
        if !prog.addresses_match {
            return Err(ClientError::LoaderBind(format!(
                "ProgramData address {} != derived {}",
                prog.programdata_address, prog.derived_programdata_address
            )));
        }
        let pd_acc = self.fetch_account_confirmed(&prog.programdata_address)?;
        let pd = crate::loader_v3::decode_loader_v3_programdata_account(&pd_acc)?;
        let bind = crate::loader_v3::bind_programdata_elf_to_local_bytes(&pd, local_so)?;
        Ok((prog, pd, bind))
    }

    pub fn get_latest_blockhash_with_commitment(&self) -> Result<(Hash, u64), ClientError> {
        self.client
            .get_latest_blockhash_with_commitment(CommitmentConfig::confirmed())
            .map_err(|e| self.rpc_err(format!("getLatestBlockhash: {e}")))
    }

    pub fn get_block_height_confirmed(&self) -> Result<u64, ClientError> {
        self.client
            .get_block_height_with_commitment(CommitmentConfig::confirmed())
            .map_err(|e| self.rpc_err(format!("getBlockHeight: {e}")))
    }

    pub fn get_balance(&self, pk: &Pubkey) -> Result<u64, ClientError> {
        self.client
            .get_balance(pk)
            .map_err(|e| self.rpc_err(format!("getBalance: {e}")))
    }

    pub fn estimate_fee(&self, tx: &Transaction) -> Result<u64, ClientError> {
        self.client
            .get_fee_for_message(tx.message())
            .map_err(|e| self.rpc_err(format!("getFeeForMessage: {e}")))
    }

    pub fn request_airdrop_bounded(
        &self,
        pubkey: &Pubkey,
        lamports: u64,
    ) -> Result<Signature, ClientError> {
        if lamports == 0 {
            return Err(ClientError::DevnetConfig(
                "airdrop lamports must be > 0".into(),
            ));
        }
        if lamports > MAX_AIRDROP_LAMPORTS {
            return Err(ClientError::DevnetConfig(format!(
                "airdrop {lamports} exceeds bound {MAX_AIRDROP_LAMPORTS} (2 SOL)"
            )));
        }
        self.client.request_airdrop(pubkey, lamports).map_err(|e| {
            self.rpc_err(format!(
                "requestAirdrop faucet failed (no wallet fallback): {e}"
            ))
        })
    }

    /// Poll airdrop signature to confirmed; timeout errors include the airdrop sig.
    pub fn confirm_airdrop_sig(&self, sig: &Signature) -> Result<(), ClientError> {
        let deadline = Instant::now() + Duration::from_secs(self.wall_deadline_secs);
        loop {
            match self.client.get_signature_statuses_with_history(&[*sig]) {
                Ok(resp) => {
                    if let Some(Some(status)) = resp.value.first() {
                        if let Some(err) = &status.err {
                            return Err(self
                                .rpc_err(format!("airdrop signature {sig} on-chain err={err:?}")));
                        }
                        if status.satisfies_commitment(CommitmentConfig::confirmed()) {
                            return Ok(());
                        }
                    }
                }
                Err(e) => {
                    if Instant::now() >= deadline {
                        return Err(self.rpc_err(format!(
                            "airdrop signature {sig} poll failed before deadline: {e}"
                        )));
                    }
                }
            }
            if Instant::now() >= deadline {
                return Err(self.rpc_err(format!(
                    "airdrop signature {sig} not confirmed within wall deadline"
                )));
            }
            thread::sleep(Duration::from_millis(400));
        }
    }

    /// One send with skip_preflight=false, preflight confirmed, max_retries=0.
    /// Any send error is treated as ambiguous; continue with known local signature.
    pub fn send_once(
        &self,
        tx: &Transaction,
        local_sig: &Signature,
    ) -> Result<SendOutcome, ClientError> {
        let config = RpcSendTransactionConfig {
            skip_preflight: false,
            preflight_commitment: Some(CommitmentLevel::Confirmed),
            encoding: None,
            max_retries: Some(0),
            min_context_slot: None,
        };
        match self.client.send_transaction_with_config(tx, config) {
            Ok(sig) => {
                if sig != *local_sig {
                    return Err(self.rpc_err(format!(
                        "sendTransaction returned unexpected signature {sig} != local {local_sig}"
                    )));
                }
                Ok(SendOutcome::Accepted { signature: sig })
            }
            Err(e) => {
                // Conservative: every send error is ambiguous; do not resend/resign.
                Ok(SendOutcome::Ambiguous {
                    signature: *local_sig,
                    send_error: self.redact_message(e.to_string()),
                })
            }
        }
    }

    /// Poll getSignatureStatuses(searchTransactionHistory=true) + getBlockHeight(confirmed).
    pub fn poll_until_confirmed_or_expired(
        &self,
        signature: &Signature,
        last_valid_block_height: u64,
        ambiguous_send_error: Option<&str>,
    ) -> Result<(), ClientError> {
        let deadline = Instant::now() + Duration::from_secs(self.wall_deadline_secs);
        let mut last_height = 0u64;
        let mut saw_unconfirmed_status = false;
        loop {
            // Block height under confirmed commitment.
            match self
                .client
                .get_block_height_with_commitment(CommitmentConfig::confirmed())
            {
                Ok(h) => last_height = h,
                Err(e) => {
                    if Instant::now() >= deadline {
                        return Err(self.rpc_err(format!(
                            "signature {signature} ambiguous timeout (getBlockHeight): {e}; prior_send={ambiguous_send_error:?}"
                        )));
                    }
                }
            }

            match self
                .client
                .get_signature_statuses_with_history(&[*signature])
            {
                Ok(resp) => {
                    let observed = resp.value.first().and_then(Option::as_ref);
                    let decision = classify_poll_observation(
                        observed.is_some(),
                        observed.is_some_and(|status| {
                            status.satisfies_commitment(CommitmentConfig::confirmed())
                        }),
                        observed.is_some_and(|status| status.err.is_some()),
                        last_height,
                        last_valid_block_height,
                    );
                    match decision {
                        PollDecision::Confirmed => return Ok(()),
                        PollDecision::OnChainError => {
                            let err = observed.and_then(|status| status.err.as_ref());
                            return Err(self.rpc_err(format!(
                                "signature {signature} on-chain transaction error: {err:?}"
                            )));
                        }
                        PollDecision::ObservedUnconfirmed => {
                            saw_unconfirmed_status = true;
                        }
                        PollDecision::CleanExpiry => {
                            return Err(self.rpc_err(format!(
                                "signature {signature} clean expiry: null status at block_height {last_height} > lastValidBlockHeight {last_valid_block_height}; prior_send={ambiguous_send_error:?}"
                            )));
                        }
                        PollDecision::Continue => {}
                    }
                }
                Err(e) => {
                    if Instant::now() >= deadline {
                        return Err(self.rpc_err(format!(
                            "signature {signature} ambiguous timeout (getSignatureStatuses): {e}; prior_send={ambiguous_send_error:?}"
                        )));
                    }
                }
            }

            if Instant::now() >= deadline {
                if saw_unconfirmed_status {
                    return Err(self.rpc_err(format!(
                        "signature {signature} ambiguous timeout: observed unconfirmed status; height={last_height} LVBH={last_valid_block_height}; prior_send={ambiguous_send_error:?}"
                    )));
                }
                if last_height > last_valid_block_height {
                    return Err(self.rpc_err(format!(
                        "signature {signature} clean expiry at wall deadline: null status and height {last_height} > LVBH {last_valid_block_height}; prior_send={ambiguous_send_error:?}"
                    )));
                }
                return Err(self.rpc_err(format!(
                    "signature {signature} ambiguous timeout: still valid (height {last_height} <= LVBH {last_valid_block_height}) but wall deadline hit; prior_send={ambiguous_send_error:?}"
                )));
            }
            thread::sleep(Duration::from_millis(400));
        }
    }

    pub fn fetch_confirmed_transaction(
        &self,
        signature_base58: &str,
    ) -> Result<ConfirmedTransactionJson, ClientError> {
        let deadline = Instant::now() + Duration::from_secs(self.wall_deadline_secs);
        let mut last_err = String::from("transaction not found / not confirmed");
        loop {
            match self.rpc_call(
                "getTransaction",
                json!([
                    signature_base58,
                    {
                        "encoding": "json",
                        "commitment": "confirmed",
                        "maxSupportedTransactionVersion": 0
                    }
                ]),
            ) {
                Ok(result) if !result.is_null() => {
                    return serde_json::from_value(result)
                        .map_err(|e| self.rpc_err(format!("decode getTransaction: {e}")));
                }
                Ok(_) => {
                    // keep last_err as not-found
                }
                Err(e) => {
                    last_err = e.to_string();
                }
            }
            if Instant::now() >= deadline {
                return Err(self.rpc_err(format!(
                    "getTransaction exhausted for signature {signature_base58}: {last_err}"
                )));
            }
            thread::sleep(Duration::from_millis(400));
        }
    }
}

pub enum SendOutcome {
    Accepted {
        signature: Signature,
    },
    Ambiguous {
        signature: Signature,
        send_error: String,
    },
}

/// Ensure payer balance >= need via bounded airdrop(s). Faucet errors have no wallet fallback.
pub fn ensure_funded(
    rpc: &RpcBundle,
    payer: &Keypair,
    need_lamports: u64,
) -> Result<u64, ClientError> {
    let mut bal = rpc.get_balance(&payer.pubkey())?;
    if bal >= need_lamports {
        return Ok(bal);
    }
    let mut granted_total = 0u64;
    while bal < need_lamports && granted_total < MAX_AIRDROP_LAMPORTS {
        let remaining = need_lamports - bal;
        let room = MAX_AIRDROP_LAMPORTS - granted_total;
        let req = remaining.min(room).min(1_000_000_000);
        if req == 0 {
            break;
        }
        let sig = rpc.request_airdrop_bounded(&payer.pubkey(), req)?;
        rpc.confirm_airdrop_sig(&sig)?;
        granted_total = granted_total.saturating_add(req);
        bal = rpc.get_balance(&payer.pubkey())?;
    }
    if bal < need_lamports {
        return Err(rpc.rpc_err(format!(
            "faucet/airdrop insufficient: balance={bal} need={need_lamports} (endpoint-relative; no wallet fallback; not success)"
        )));
    }
    Ok(bal)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn poll_observation_matrix_distinguishes_landed_from_clean_expiry() {
        let lvbh = 100;
        assert_eq!(
            classify_poll_observation(true, true, false, 99, lvbh),
            PollDecision::Confirmed
        );
        assert_eq!(
            classify_poll_observation(true, false, true, 99, lvbh),
            PollDecision::OnChainError
        );
        assert_eq!(
            classify_poll_observation(true, false, false, 101, lvbh),
            PollDecision::ObservedUnconfirmed,
            "a present Processed status must not become clean expiry after LVBH"
        );
        assert_eq!(
            classify_poll_observation(false, false, false, 101, lvbh),
            PollDecision::CleanExpiry
        );
        assert_eq!(
            classify_poll_observation(false, false, false, 100, lvbh),
            PollDecision::Continue
        );
    }

    #[test]
    fn rpc_error_redaction_covers_normalized_url_spelling() {
        let rpc = RpcBundle::new("https://example.invalid", 1, 1).unwrap();
        let rendered = rpc.redact_message("transport failed for https://example.invalid/");
        assert_eq!(rendered, "transport failed for https://example.invalid");

        let tokenized =
            RpcBundle::new("https://example.invalid/never-echo-token?q=secret", 1, 1).unwrap();
        let rendered = tokenized.redact_message(
            "transport failed for https://example.invalid/never-echo-token?q=secret",
        );
        assert!(!rendered.contains("never-echo"));
        assert!(!rendered.contains("secret"));
    }
}
