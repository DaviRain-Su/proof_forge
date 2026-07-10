//! Deploy / call / view helpers + account key projection.

use std::path::Path;

use anyhow::{bail, ensure, Context, Result};
use near_gas::NearGas;
use near_workspaces::network::Sandbox;
use near_workspaces::result::ExecutionFinalResult;
use near_workspaces::{Account, Contract, Worker};

use crate::report::{SideKind, SideReport, StepReport};

pub(crate) fn sha256_32(data: &[u8]) -> [u8; 32] {
    // FIPS 180-4 SHA-256 (same projection as EmitWat / compare driver).
    struct Sha256 {
        h: [u32; 8],
        len: u64,
        buf: [u8; 64],
        buf_len: usize,
    }
    impl Sha256 {
        fn new() -> Self {
            Self {
                h: [
                    0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c,
                    0x1f83d9ab, 0x5be0cd19,
                ],
                len: 0,
                buf: [0; 64],
                buf_len: 0,
            }
        }
        fn update(&mut self, data: &[u8]) {
            for &b in data {
                self.buf[self.buf_len] = b;
                self.buf_len += 1;
                self.len += 1;
                if self.buf_len == 64 {
                    self.compress();
                    self.buf_len = 0;
                }
            }
        }
        fn compress(&mut self) {
            const K: [u32; 64] = [
                0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4,
                0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe,
                0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f,
                0x4a7484aa, 0x5cb0a9dc, 0x76f988da, 0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
                0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc,
                0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
                0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070, 0x19a4c116,
                0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
                0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7,
                0xc67178f2,
            ];
            let mut w = [0u32; 64];
            for i in 0..16 {
                w[i] = u32::from_be_bytes([
                    self.buf[i * 4],
                    self.buf[i * 4 + 1],
                    self.buf[i * 4 + 2],
                    self.buf[i * 4 + 3],
                ]);
            }
            for i in 16..64 {
                let s0 = w[i - 15].rotate_right(7) ^ w[i - 15].rotate_right(18) ^ (w[i - 15] >> 3);
                let s1 = w[i - 2].rotate_right(17) ^ w[i - 2].rotate_right(19) ^ (w[i - 2] >> 10);
                w[i] = w[i - 16]
                    .wrapping_add(s0)
                    .wrapping_add(w[i - 7])
                    .wrapping_add(s1);
            }
            let (mut a, mut b, mut c, mut d, mut e, mut f, mut g, mut h) = (
                self.h[0], self.h[1], self.h[2], self.h[3], self.h[4], self.h[5], self.h[6],
                self.h[7],
            );
            for i in 0..64 {
                let s1 = e.rotate_right(6) ^ e.rotate_right(11) ^ e.rotate_right(25);
                let ch = (e & f) ^ ((!e) & g);
                let t1 = h
                    .wrapping_add(s1)
                    .wrapping_add(ch)
                    .wrapping_add(K[i])
                    .wrapping_add(w[i]);
                let s0 = a.rotate_right(2) ^ a.rotate_right(13) ^ a.rotate_right(22);
                let maj = (a & b) ^ (a & c) ^ (b & c);
                let t2 = s0.wrapping_add(maj);
                h = g;
                g = f;
                f = e;
                e = d.wrapping_add(t1);
                d = c;
                c = b;
                b = a;
                a = t1.wrapping_add(t2);
            }
            self.h[0] = self.h[0].wrapping_add(a);
            self.h[1] = self.h[1].wrapping_add(b);
            self.h[2] = self.h[2].wrapping_add(c);
            self.h[3] = self.h[3].wrapping_add(d);
            self.h[4] = self.h[4].wrapping_add(e);
            self.h[5] = self.h[5].wrapping_add(f);
            self.h[6] = self.h[6].wrapping_add(g);
            self.h[7] = self.h[7].wrapping_add(h);
        }
        fn finalize(mut self) -> [u8; 32] {
            let bit_len = self.len * 8;
            self.update(&[0x80]);
            while self.buf_len != 56 {
                self.update(&[0x00]);
            }
            self.update(&bit_len.to_be_bytes());
            let mut out = [0u8; 32];
            for (i, &v) in self.h.iter().enumerate() {
                out[i * 4..(i + 1) * 4].copy_from_slice(&v.to_be_bytes());
            }
            out
        }
    }
    let mut s = Sha256::new();
    s.update(data);
    s.finalize()
}

pub(crate) fn account_hash_borsh(account: &str, amount: Option<u64>) -> Vec<u8> {
    let mut v = sha256_32(account.as_bytes()).to_vec();
    if let Some(a) = amount {
        v.extend_from_slice(&a.to_le_bytes());
    }
    v
}

pub(crate) fn account_u64(account: &str) -> u64 {
    u64::from_le_bytes(sha256_32(account.as_bytes())[..8].try_into().unwrap())
}

pub(crate) async fn deploy_with_metrics(
    worker: &Worker<Sandbox>,
    wasm: &[u8],
) -> Result<(Contract, u64, u64)> {
    let account: Account = worker
        .dev_create_account()
        .await
        .context("dev_create_account")?;
    let execution = account
        .deploy(wasm)
        .await
        .context("account.deploy")?;
    let deploy_gas = execution.details.total_gas_burnt.as_gas();
    let contract = execution
        .into_result()
        .map_err(|e| anyhow::anyhow!("deploy failed: {e:?}"))?;
    let storage = contract
        .view_account()
        .await
        .context("view_account after deploy")?
        .storage_usage;
    Ok((contract, deploy_gas, storage))
}

pub(crate) async fn refresh_storage(contract: &Contract) -> Result<u64> {
    Ok(contract.view_account().await?.storage_usage)
}


pub(crate) async fn call_raw(contract: &Contract, method: &str, args: &[u8]) -> Result<StepReport> {
    let outcome = contract
        .call(method)
        .args(args.to_vec())
        .gas(NearGas::from_tgas(100))
        .transact()
        .await
        .with_context(|| format!("call `{method}`"))?;
    Ok(step_from_outcome(method, "call", outcome))
}

pub(crate) async fn call_json(
    contract: &Contract,
    method: &str,
    args: serde_json::Value,
) -> Result<StepReport> {
    let outcome = contract
        .call(method)
        .args_json(args)
        .gas(NearGas::from_tgas(100))
        .transact()
        .await
        .with_context(|| format!("call `{method}` json"))?;
    Ok(step_from_outcome(method, "call", outcome))
}

pub(crate) async fn call_raw_deposit(
    contract: &Contract,
    method: &str,
    args: &[u8],
    deposit_yocto: u128,
) -> Result<StepReport> {
    let outcome = contract
        .call(method)
        .args(args.to_vec())
        .deposit(near_workspaces::types::NearToken::from_yoctonear(deposit_yocto))
        .gas(NearGas::from_tgas(100))
        .transact()
        .await
        .with_context(|| format!("call `{method}` deposit"))?;
    Ok(step_from_outcome(method, "call", outcome))
}

pub(crate) async fn call_json_deposit(
    contract: &Contract,
    method: &str,
    args: serde_json::Value,
    deposit_yocto: u128,
) -> Result<StepReport> {
    let outcome = contract
        .call(method)
        .args_json(args)
        .deposit(near_workspaces::types::NearToken::from_yoctonear(deposit_yocto))
        .gas(NearGas::from_tgas(100))
        .transact()
        .await
        .with_context(|| format!("call `{method}` deposit json"))?;
    Ok(step_from_outcome(method, "call", outcome))
}

pub(crate) async fn view_raw_u64(contract: &Contract, method: &str) -> Result<StepReport> {
    view_raw_u64_args(contract, method, &[]).await
}

pub(crate) async fn view_raw_u64_args(
    contract: &Contract,
    method: &str,
    args: &[u8],
) -> Result<StepReport> {
    let details = contract
        .view(method)
        .args(args.to_vec())
        .await
        .with_context(|| format!("view `{method}`"))?;
    let bytes = details.result;
    let return_u64 = decode_le_u64(&bytes)?;
    Ok(StepReport {
        call: method.into(),
        kind: "view".into(),
        ok: true,
        gas_burnt: None,
        return_u64: Some(return_u64),
        logs: details.logs,
        error: None,
    })
}

pub(crate) async fn view_json_u64(
    contract: &Contract,
    method: &str,
    args: serde_json::Value,
) -> Result<StepReport> {
    let details = contract
        .view(method)
        .args_json(args)
        .await
        .with_context(|| format!("view `{method}` json"))?;
    let val: u64 = details.json().context("json u64")?;
    Ok(StepReport {
        call: method.into(),
        kind: "view".into(),
        ok: true,
        gas_burnt: None,
        return_u64: Some(val),
        logs: details.logs,
        error: None,
    })
}

pub(crate) fn decode_le_u64(bytes: &[u8]) -> Result<u64> {
    if bytes.len() == 8 {
        return Ok(u64::from_le_bytes(bytes.try_into().unwrap()));
    }
    if let Ok(v) = serde_json::from_slice::<u64>(bytes) {
        return Ok(v);
    }
    bail!("expected LE u64 (8 bytes), got {} bytes: {bytes:02x?}", bytes.len());
}

pub(crate) fn step_from_outcome(call: &str, kind: &str, outcome: ExecutionFinalResult) -> StepReport {
    let gas = outcome.total_gas_burnt.as_gas();
    let logs: Vec<String> = outcome.logs().iter().map(|s| (*s).to_string()).collect();
    if outcome.is_success() {
        StepReport {
            call: call.into(),
            kind: kind.into(),
            ok: true,
            gas_burnt: Some(gas),
            return_u64: None,
            logs,
            error: None,
        }
    } else {
        let err = format!("{:?}", outcome.into_result().err());
        StepReport {
            call: call.into(),
            kind: kind.into(),
            ok: false,
            gas_burnt: Some(gas),
            return_u64: None,
            logs,
            error: Some(err),
        }
    }
}

pub(crate) fn ensure_ok(step: &StepReport, label: &str) -> Result<()> {
    if !step.ok {
        bail!(
            "{label} failed: {}",
            step.error.as_deref().unwrap_or("unknown")
        );
    }
    Ok(())
}

pub(crate) fn ensure_ret(step: &StepReport, expected: u64, label: &str) -> Result<()> {
    if step.return_u64 != Some(expected) {
        bail!("{label}: expected {expected}, got {:?}", step.return_u64);
    }
    Ok(())
}

pub(crate) fn ensure_file(path: &Path, label: &str) -> Result<()> {
    if !path.is_file() {
        bail!("{label} missing: {}", path.display());
    }
    Ok(())
}

pub(crate) fn ratio(num: u64, den: u64) -> Option<f64> {
    if den == 0 {
        None
    } else {
        Some(round3(num as f64 / den as f64))
    }
}

pub(crate) fn fmt_opt_ratio(r: Option<f64>) -> String {
    r.map(|v| format!("{v:.3}")).unwrap_or_else(|| "n/a".into())
}

pub(crate) fn round3(v: f64) -> f64 {
    (v * 1000.0).round() / 1000.0
}



/// Mutable per-side scenario runner — collapses deploy/step/call_gas boilerplate.
pub(crate) struct SideCtx {
    pub contract: Contract,
    pub wasm_bytes: u64,
    pub deploy_gas: u64,
    pub kind: SideKind,
    pub steps: Vec<StepReport>,
    pub call_gas: u64,
}

#[allow(dead_code)]
impl SideCtx {
    pub async fn open(worker: &Worker<Sandbox>, wasm_path: &Path, kind: SideKind) -> Result<Self> {
        let wasm = std::fs::read(wasm_path)?;
        let wasm_bytes = wasm.len() as u64;
        let (contract, deploy_gas, _) = deploy_with_metrics(worker, &wasm).await?;
        Ok(Self {
            contract,
            wasm_bytes,
            deploy_gas,
            kind,
            steps: Vec::new(),
            call_gas: 0,
        })
    }

    pub fn is_pf(&self) -> bool {
        matches!(self.kind, SideKind::ProofForge)
    }

    pub async fn call_raw(&mut self, method: &str, args: &[u8], label: &str) -> Result<()> {
        let s = call_raw(&self.contract, method, args).await?;
        self.call_gas = self.call_gas.saturating_add(s.gas_burnt.unwrap_or(0));
        ensure_ok(&s, label)?;
        self.steps.push(s);
        Ok(())
    }

    pub async fn call_json(&mut self, method: &str, args: serde_json::Value, label: &str) -> Result<()> {
        let s = call_json(&self.contract, method, args).await?;
        self.call_gas = self.call_gas.saturating_add(s.gas_burnt.unwrap_or(0));
        ensure_ok(&s, label)?;
        self.steps.push(s);
        Ok(())
    }

    pub async fn call_raw_deposit(
        &mut self,
        method: &str,
        args: &[u8],
        deposit: u128,
        label: &str,
    ) -> Result<()> {
        let s = call_raw_deposit(&self.contract, method, args, deposit).await?;
        self.call_gas = self.call_gas.saturating_add(s.gas_burnt.unwrap_or(0));
        ensure_ok(&s, label)?;
        self.steps.push(s);
        Ok(())
    }

    pub async fn call_json_deposit(
        &mut self,
        method: &str,
        args: serde_json::Value,
        deposit: u128,
        label: &str,
    ) -> Result<()> {
        let s = call_json_deposit(&self.contract, method, args, deposit).await?;
        self.call_gas = self.call_gas.saturating_add(s.gas_burnt.unwrap_or(0));
        ensure_ok(&s, label)?;
        self.steps.push(s);
        Ok(())
    }

    pub async fn view_raw_u64(&mut self, method: &str, label: &str, expect: Option<u64>) -> Result<()> {
        let s = view_raw_u64(&self.contract, method).await?;
        ensure_ok(&s, label)?;
        if let Some(e) = expect {
            ensure_ret(&s, e, label)?;
        }
        self.steps.push(s);
        Ok(())
    }

    pub async fn view_raw_u64_args(
        &mut self,
        method: &str,
        args: &[u8],
        label: &str,
        expect: Option<u64>,
    ) -> Result<()> {
        let s = view_raw_u64_args(&self.contract, method, args).await?;
        ensure_ok(&s, label)?;
        if let Some(e) = expect {
            ensure_ret(&s, e, label)?;
        }
        self.steps.push(s);
        Ok(())
    }

    pub async fn view_json_u64(
        &mut self,
        method: &str,
        args: serde_json::Value,
        label: &str,
        expect: Option<u64>,
    ) -> Result<()> {
        let s = view_json_u64(&self.contract, method, args).await?;
        ensure_ok(&s, label)?;
        if let Some(e) = expect {
            ensure_ret(&s, e, label)?;
        }
        self.steps.push(s);
        Ok(())
    }

    /// View a 1-byte bool return (0/1), common for `returns(.bool)` on EmitWat.
    pub async fn view_raw_bool(
        &mut self,
        method: &str,
        args: &[u8],
        label: &str,
        expect: Option<bool>,
    ) -> Result<bool> {
        let details = self
            .contract
            .view(method)
            .args(args.to_vec())
            .await
            .with_context(|| format!("view `{method}` bool"))?;
        let bytes = details.result;
        let val = match bytes.as_slice() {
            [0] | [] => false,
            [1] => true,
            // Some hosts return LE u64 0/1
            b if b.len() == 8 => u64::from_le_bytes(b.try_into().unwrap()) != 0,
            other => bail!("{label}: expected bool bytes, got {other:02x?}"),
        };
        if let Some(exp) = expect {
            ensure!(val == exp, "{label}: expected {exp}, got {val}");
        }
        self.steps.push(StepReport {
            call: method.into(),
            kind: "view".into(),
            ok: true,
            gas_burnt: None,
            return_u64: Some(u64::from(val)),
            logs: details.logs,
            error: None,
        });
        Ok(val)
    }

    /// View JSON bool.
    pub async fn view_json_bool(
        &mut self,
        method: &str,
        args: serde_json::Value,
        label: &str,
        expect: Option<bool>,
    ) -> Result<bool> {
        let details = self
            .contract
            .view(method)
            .args_json(args)
            .await
            .with_context(|| format!("view `{method}` json bool"))?;
        let val: bool = details.json().context("json bool")?;
        if let Some(exp) = expect {
            ensure!(val == exp, "{label}: expected {exp}, got {val}");
        }
        self.steps.push(StepReport {
            call: method.into(),
            kind: "view".into(),
            ok: true,
            gas_burnt: None,
            return_u64: Some(u64::from(val)),
            logs: details.logs,
            error: None,
        });
        Ok(val)
    }

    /// View raw bytes (e.g. hash-width `owner` → 32-byte return).
    pub async fn view_raw_bytes(
        &mut self,
        method: &str,
        label: &str,
        expect: Option<&[u8]>,
    ) -> Result<Vec<u8>> {
        let details = self
            .contract
            .view(method)
            .args(Vec::new())
            .await
            .with_context(|| format!("view `{method}` bytes"))?;
        let bytes = details.result;
        if let Some(exp) = expect {
            ensure!(
                bytes.as_slice() == exp,
                "{label}: expected {exp:02x?}, got {bytes:02x?}"
            );
        }
        self.steps.push(StepReport {
            call: method.into(),
            kind: "view".into(),
            ok: true,
            gas_burnt: None,
            return_u64: None,
            logs: details.logs,
            error: None,
        });
        Ok(bytes)
    }

    /// View JSON `[u8; N]` / `Vec<u8>` returned as a JSON number array.
    pub async fn view_json_bytes(
        &mut self,
        method: &str,
        args: serde_json::Value,
        label: &str,
        expect: Option<&[u8]>,
    ) -> Result<Vec<u8>> {
        let details = self
            .contract
            .view(method)
            .args_json(args)
            .await
            .with_context(|| format!("view `{method}` json bytes"))?;
        let nums: Vec<u8> = details.json().context("json byte array")?;
        if let Some(exp) = expect {
            ensure!(
                nums.as_slice() == exp,
                "{label}: expected {exp:02x?}, got {nums:02x?}"
            );
        }
        self.steps.push(StepReport {
            call: method.into(),
            kind: "view".into(),
            ok: true,
            gas_burnt: None,
            return_u64: None,
            logs: details.logs,
            error: None,
        });
        Ok(nums)
    }

    pub fn push_step(&mut self, s: StepReport) {
        self.steps.push(s);
    }

    pub async fn finish(self) -> Result<SideReport> {
        let storage = refresh_storage(&self.contract).await?;
        Ok(SideReport {
            label: self.kind.label().into(),
            account_id: self.contract.id().to_string(),
            wasm_bytes: self.wasm_bytes,
            deploy_gas_burnt: self.deploy_gas,
            storage_usage_bytes: storage,
            call_gas_burnt: self.call_gas,
            total_gas_burnt: self.deploy_gas.saturating_add(self.call_gas),
            steps: self.steps,
        })
    }
}
