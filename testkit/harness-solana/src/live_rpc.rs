use std::path::Path;
use std::str::FromStr;
use std::thread;
use std::time::Duration;

use anyhow::{anyhow, bail, ensure, Context, Result};
use base64::{engine::general_purpose::STANDARD as BASE64, Engine as _};
use reqwest::blocking::Client;
use serde::de::DeserializeOwned;
use serde::Deserialize;
use serde_json::{json, Value};
use solana_address::Address;
use solana_instruction::Instruction;
use solana_keypair::{read_keypair_file, Keypair};
use solana_signer::Signer;
use solana_transaction::{Hash, Transaction};

pub struct LiveRpc {
    url: String,
    client: Client,
}

pub struct LiveAccountInfo {
    pub data: Vec<u8>,
    pub lamports: u64,
    pub owner: Address,
}

impl LiveRpc {
    pub fn new(url: impl Into<String>) -> Self {
        Self {
            url: url.into(),
            client: Client::new(),
        }
    }

    pub fn latest_blockhash(&self) -> Result<Hash> {
        let response: LatestBlockhashResponse =
            self.call("getLatestBlockhash", json!([{ "commitment": "confirmed" }]))?;
        Hash::from_str(&response.value.blockhash)
            .with_context(|| format!("invalid latest blockhash {}", response.value.blockhash))
    }

    pub fn minimum_balance_for_rent_exemption(&self, space: u64) -> Result<u64> {
        self.call("getMinimumBalanceForRentExemption", json!([space]))
    }

    pub fn epoch_schedule(&self) -> Result<EpochSchedule> {
        self.call("getEpochSchedule", json!([]))
    }

    pub fn balance(&self, account: Address) -> Result<u64> {
        let response: BalanceResponse = self.call(
            "getBalance",
            json!([
                account.to_string(),
                {
                    "commitment": "confirmed"
                }
            ]),
        )?;
        Ok(response.value)
    }

    pub fn send_and_confirm(
        &self,
        instructions: &[Instruction],
        signers: &[&Keypair],
    ) -> Result<String> {
        ensure!(
            !signers.is_empty(),
            "transaction requires at least the payer signer"
        );
        let encoded = self.encode_signed_transaction(instructions, signers)?;
        let signature: String = self.call(
            "sendTransaction",
            json!([
                encoded,
                {
                    "encoding": "base64",
                    "skipPreflight": false,
                    "preflightCommitment": "confirmed"
                }
            ]),
        )?;
        self.confirm_signature(&signature)?;
        Ok(signature)
    }

    pub fn simulate_return_data(
        &self,
        instructions: &[Instruction],
        signers: &[&Keypair],
        expected_program_id: Address,
    ) -> Result<Vec<u8>> {
        let encoded = self.encode_signed_transaction(instructions, signers)?;
        let response: SimulateResponse = self.call(
            "simulateTransaction",
            json!([
                encoded,
                {
                    "encoding": "base64",
                    "sigVerify": false,
                    "replaceRecentBlockhash": true,
                    "commitment": "confirmed"
                }
            ]),
        )?;
        if let Some(err) = response.value.err {
            bail!("simulation returned error: {err}");
        }
        let return_data = response
            .value
            .return_data
            .context("simulation did not return data")?;
        ensure!(
            return_data.program_id == expected_program_id.to_string(),
            "return data came from {}, expected {}",
            return_data.program_id,
            expected_program_id
        );
        decode_base64_pair(return_data.data, "return data")
    }

    pub fn simulate_return_u64(
        &self,
        instructions: &[Instruction],
        signers: &[&Keypair],
        expected_program_id: Address,
    ) -> Result<u64> {
        let bytes = self.simulate_return_data(instructions, signers, expected_program_id)?;
        read_u64_le(&bytes)
    }

    pub fn transaction_logs(&self, signature: &str) -> Result<Vec<String>> {
        for _ in 0..60 {
            let response: Option<TransactionResponse> = self.call_nullable(
                "getTransaction",
                json!([
                    signature,
                    {
                        "commitment": "confirmed",
                        "maxSupportedTransactionVersion": 0
                    }
                ]),
            )?;
            if let Some(tx) = response {
                if let Some(logs) = tx.meta.and_then(|meta| meta.log_messages) {
                    if !logs.is_empty() {
                        return Ok(logs);
                    }
                }
            }
            thread::sleep(Duration::from_millis(500));
        }
        bail!("transaction logs not available for {signature}")
    }

    pub fn transaction_slot(&self, signature: &str) -> Result<u64> {
        for _ in 0..60 {
            let response: Option<TransactionResponse> = self.call_nullable(
                "getTransaction",
                json!([
                    signature,
                    {
                        "commitment": "confirmed",
                        "maxSupportedTransactionVersion": 0
                    }
                ]),
            )?;
            if let Some(tx) = response {
                return Ok(tx.slot);
            }
            thread::sleep(Duration::from_millis(500));
        }
        bail!("transaction not available for {signature}")
    }

    pub fn account_info_optional(&self, account: Address) -> Result<Option<LiveAccountInfo>> {
        let response: AccountInfoResponse = self.call(
            "getAccountInfo",
            json!([
                account.to_string(),
                {
                    "encoding": "base64",
                    "commitment": "confirmed"
                }
            ]),
        )?;
        response
            .value
            .map(|account_info| account_info.into_live_account_info())
            .transpose()
    }

    pub fn account_info(&self, account: Address) -> Result<LiveAccountInfo> {
        self.account_info_optional(account)?
            .with_context(|| format!("account not found: {account}"))
    }

    pub fn account_data(&self, account: Address) -> Result<Vec<u8>> {
        Ok(self.account_info(account)?.data)
    }

    pub fn account_data_u64(&self, account: Address) -> Result<u64> {
        let bytes = self.account_data(account)?;
        read_u64_le(&bytes)
    }

    fn encode_signed_transaction(
        &self,
        instructions: &[Instruction],
        signers: &[&Keypair],
    ) -> Result<String> {
        ensure!(
            !signers.is_empty(),
            "transaction requires at least one signer"
        );
        let payer = signers[0].pubkey();
        let blockhash = self.latest_blockhash()?;
        let mut tx = Transaction::new_with_payer(instructions, Some(&payer));
        tx.try_sign(signers, blockhash)
            .context("failed to sign transaction")?;
        let bytes = bincode::serialize(&tx).context("failed to serialize transaction")?;
        Ok(BASE64.encode(bytes))
    }

    fn confirm_signature(&self, signature: &str) -> Result<()> {
        for _ in 0..60 {
            let response: SignatureStatusesResponse = self.call(
                "getSignatureStatuses",
                json!([[signature], { "searchTransactionHistory": true }]),
            )?;
            if let Some(Some(status)) = response.value.into_iter().next() {
                if let Some(err) = status.err {
                    bail!("transaction {signature} failed: {err}");
                }
                match status.confirmation_status.as_deref() {
                    Some("confirmed") | Some("finalized") => return Ok(()),
                    _ => {}
                }
            }
            thread::sleep(Duration::from_millis(500));
        }
        bail!("timed out waiting for transaction {signature} confirmation")
    }

    fn call<T: DeserializeOwned>(&self, method: &str, params: Value) -> Result<T> {
        let response: RpcResponse<T> = self
            .client
            .post(&self.url)
            .json(&json!({
                "jsonrpc": "2.0",
                "id": 1,
                "method": method,
                "params": params,
            }))
            .send()
            .with_context(|| format!("RPC {method} request failed"))?
            .error_for_status()
            .with_context(|| format!("RPC {method} returned HTTP error"))?
            .json()
            .with_context(|| format!("RPC {method} returned invalid JSON"))?;
        if let Some(error) = response.error {
            bail!(
                "RPC {method} failed: code={} message={}",
                error.code,
                error.message
            );
        }
        response
            .result
            .with_context(|| format!("RPC {method} response missing result"))
    }

    fn call_nullable<T: DeserializeOwned>(&self, method: &str, params: Value) -> Result<Option<T>> {
        let response: Value = self
            .client
            .post(&self.url)
            .json(&json!({
                "jsonrpc": "2.0",
                "id": 1,
                "method": method,
                "params": params,
            }))
            .send()
            .with_context(|| format!("RPC {method} request failed"))?
            .error_for_status()
            .with_context(|| format!("RPC {method} returned HTTP error"))?
            .json()
            .with_context(|| format!("RPC {method} returned invalid JSON"))?;
        if let Some(error) = response.get("error").filter(|value| !value.is_null()) {
            let error: RpcError = serde_json::from_value(error.clone())
                .with_context(|| format!("RPC {method} returned invalid error JSON"))?;
            bail!(
                "RPC {method} failed: code={} message={}",
                error.code,
                error.message
            );
        }
        let result = response
            .get("result")
            .with_context(|| format!("RPC {method} response missing result"))?;
        if result.is_null() {
            return Ok(None);
        }
        serde_json::from_value(result.clone())
            .map(Some)
            .with_context(|| format!("RPC {method} returned invalid result JSON"))
    }
}

pub fn read_keypair(path: impl AsRef<Path>) -> Result<Keypair> {
    let path = path.as_ref();
    read_keypair_file(path)
        .map_err(|err| anyhow!("failed to read keypair {}: {err}", path.display()))
}

pub fn create_program_state(
    rpc: &LiveRpc,
    payer: &Keypair,
    program_id: Address,
    space: u64,
) -> Result<Keypair> {
    let state = Keypair::new();
    let lamports = rpc.minimum_balance_for_rent_exemption(space)?;
    let ix = solana_system_interface::instruction::create_account(
        &payer.pubkey(),
        &state.pubkey(),
        lamports,
        space,
        &program_id,
    );
    rpc.send_and_confirm(&[ix], &[payer, &state])?;
    Ok(state)
}

pub fn read_u64_le(data: &[u8]) -> Result<u64> {
    read_u64_le_at(data, 0)
}

pub fn read_u64_le_at(data: &[u8], offset: usize) -> Result<u64> {
    let end = offset.checked_add(8).context("u64 read offset overflow")?;
    let bytes: [u8; 8] = data
        .get(offset..end)
        .with_context(|| format!("expected at least {end} bytes"))?
        .try_into()
        .expect("slice length is fixed");
    Ok(u64::from_le_bytes(bytes))
}

fn decode_base64_pair(data: (String, String), label: &str) -> Result<Vec<u8>> {
    let (encoded, encoding) = data;
    ensure!(
        encoding == "base64",
        "expected base64 {label}, got {encoding}"
    );
    BASE64
        .decode(encoded)
        .with_context(|| format!("failed to decode {label}"))
}

#[derive(Debug, Deserialize)]
struct RpcResponse<T> {
    result: Option<T>,
    error: Option<RpcError>,
}

#[derive(Debug, Deserialize)]
struct RpcError {
    code: i64,
    message: String,
}

#[derive(Debug, Deserialize)]
struct LatestBlockhashResponse {
    value: LatestBlockhashValue,
}

#[derive(Debug, Deserialize)]
struct LatestBlockhashValue {
    blockhash: String,
}

#[derive(Debug, Deserialize)]
struct BalanceResponse {
    value: u64,
}

#[derive(Debug, Deserialize)]
pub struct EpochSchedule {
    #[serde(rename = "slotsPerEpoch")]
    pub slots_per_epoch: u64,
    #[serde(rename = "leaderScheduleSlotOffset")]
    pub leader_schedule_slot_offset: u64,
    pub warmup: bool,
    #[serde(rename = "firstNormalEpoch")]
    pub first_normal_epoch: u64,
    #[serde(rename = "firstNormalSlot")]
    pub first_normal_slot: u64,
}

#[derive(Debug, Deserialize)]
struct AccountInfoResponse {
    value: Option<AccountInfo>,
}

#[derive(Debug, Deserialize)]
struct AccountInfo {
    data: (String, String),
    lamports: u64,
    owner: String,
}

impl AccountInfo {
    fn into_live_account_info(self) -> Result<LiveAccountInfo> {
        let owner = Address::from_str(&self.owner)
            .with_context(|| format!("invalid account owner {}", self.owner))?;
        Ok(LiveAccountInfo {
            data: decode_base64_pair(self.data, "account data")?,
            lamports: self.lamports,
            owner,
        })
    }
}

#[derive(Debug, Deserialize)]
struct SimulateResponse {
    value: SimulateValue,
}

#[derive(Debug, Deserialize)]
struct SimulateValue {
    err: Option<Value>,
    #[serde(rename = "returnData")]
    return_data: Option<ReturnData>,
}

#[derive(Debug, Deserialize)]
struct ReturnData {
    #[serde(rename = "programId")]
    program_id: String,
    data: (String, String),
}

#[derive(Debug, Deserialize)]
struct TransactionResponse {
    slot: u64,
    meta: Option<TransactionMeta>,
}

#[derive(Debug, Deserialize)]
struct TransactionMeta {
    #[serde(rename = "logMessages")]
    log_messages: Option<Vec<String>>,
}

#[derive(Debug, Deserialize)]
struct SignatureStatusesResponse {
    value: Vec<Option<SignatureStatus>>,
}

#[derive(Debug, Deserialize)]
struct SignatureStatus {
    err: Option<Value>,
    #[serde(rename = "confirmationStatus")]
    confirmation_status: Option<String>,
}
