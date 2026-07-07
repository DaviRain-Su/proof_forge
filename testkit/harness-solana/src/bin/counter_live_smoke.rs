use std::env;
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
use solana_instruction::{AccountMeta, Instruction};
use solana_keypair::{read_keypair_file, Keypair};
use solana_signer::Signer;
use solana_transaction::{Hash, Transaction};

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

    let rpc = Rpc::new(rpc_url);
    let payer = read_keypair_file(&payer_path)
        .map_err(|err| anyhow!("failed to read payer keypair {payer_path}: {err}"))?;
    let program_id = Address::from_str(&program_id_value)
        .with_context(|| format!("invalid program id {program_id_value}"))?;
    let counter = Keypair::new();

    let rent_lamports = rpc.minimum_balance_for_rent_exemption(8)?;
    let create_counter = solana_system_interface::instruction::create_account(
        &payer.pubkey(),
        &counter.pubkey(),
        rent_lamports,
        8,
        &program_id,
    );
    rpc.send_and_confirm(&[create_counter], &[&payer, &counter])
        .context("failed to create counter account")?;

    send_counter_instruction(&rpc, &payer, program_id, counter.pubkey(), 0)
        .context("initialize transaction failed")?;
    let after_initialize = rpc
        .account_data_u64(counter.pubkey())
        .context("failed to fetch counter after initialize")?;
    ensure!(
        after_initialize == 0,
        "initialize expected counter=0, got {after_initialize}"
    );

    send_counter_instruction(&rpc, &payer, program_id, counter.pubkey(), 1)
        .context("first increment transaction failed")?;
    let after_increment = rpc
        .account_data_u64(counter.pubkey())
        .context("failed to fetch counter after first increment")?;
    ensure!(
        after_increment == 1,
        "increment expected counter=1, got {after_increment}"
    );

    send_counter_instruction(&rpc, &payer, program_id, counter.pubkey(), 1)
        .context("second increment transaction failed")?;
    let after_second_increment = rpc
        .account_data_u64(counter.pubkey())
        .context("failed to fetch counter after second increment")?;
    ensure!(
        after_second_increment == 2,
        "second increment expected counter=2, got {after_second_increment}"
    );

    let get_ix = counter_instruction(program_id, counter.pubkey(), 2);
    let returned = rpc
        .simulate_return_u64(&[get_ix], &[&payer], program_id)
        .context("get simulation failed")?;
    ensure!(returned == 2, "get expected return_data=2, got {returned}");

    println!(
        "{}",
        json!({
            "programId": program_id.to_string(),
            "counter": counter.pubkey().to_string(),
            "afterInitialize": after_initialize,
            "afterIncrement": after_increment,
            "afterSecondIncrement": after_second_increment,
            "getReturnData": returned,
        })
    );

    Ok(())
}

fn send_counter_instruction(
    rpc: &Rpc,
    payer: &Keypair,
    program_id: Address,
    counter: Address,
    tag: u8,
) -> Result<String> {
    rpc.send_and_confirm(&[counter_instruction(program_id, counter, tag)], &[payer])
}

fn counter_instruction(program_id: Address, counter: Address, tag: u8) -> Instruction {
    Instruction {
        program_id,
        accounts: vec![AccountMeta::new(counter, false)],
        data: vec![tag],
    }
}

struct Rpc {
    url: String,
    client: Client,
}

impl Rpc {
    fn new(url: String) -> Self {
        Self {
            url,
            client: Client::new(),
        }
    }

    fn latest_blockhash(&self) -> Result<Hash> {
        let response: LatestBlockhashResponse =
            self.call("getLatestBlockhash", json!([{ "commitment": "confirmed" }]))?;
        Hash::from_str(&response.value.blockhash)
            .with_context(|| format!("invalid latest blockhash {}", response.value.blockhash))
    }

    fn minimum_balance_for_rent_exemption(&self, space: u64) -> Result<u64> {
        self.call("getMinimumBalanceForRentExemption", json!([space]))
    }

    fn send_and_confirm(
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

    fn simulate_return_u64(
        &self,
        instructions: &[Instruction],
        signers: &[&Keypair],
        expected_program_id: Address,
    ) -> Result<u64> {
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
        let bytes = decode_base64_pair(return_data.data, "return data")?;
        read_u64_le(&bytes)
    }

    fn account_data_u64(&self, account: Address) -> Result<u64> {
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
        let account_info = response
            .value
            .with_context(|| format!("counter account not found: {account}"))?;
        let bytes = decode_base64_pair(account_info.data, "account data")?;
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

fn read_u64_le(data: &[u8]) -> Result<u64> {
    let bytes: [u8; 8] = data
        .get(..8)
        .context("expected at least 8 bytes")?
        .try_into()
        .expect("slice length is fixed");
    Ok(u64::from_le_bytes(bytes))
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
struct AccountInfoResponse {
    value: Option<AccountInfo>,
}

#[derive(Debug, Deserialize)]
struct AccountInfo {
    data: (String, String),
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
struct SignatureStatusesResponse {
    value: Vec<Option<SignatureStatus>>,
}

#[derive(Debug, Deserialize)]
struct SignatureStatus {
    err: Option<Value>,
    #[serde(rename = "confirmationStatus")]
    confirmation_status: Option<String>,
}
