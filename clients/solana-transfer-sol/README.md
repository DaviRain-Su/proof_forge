# solana-transfer-sol

Engineering-state Rust CLI that **consumes a ProofForge `TransferSol` product OutputSet**
(`proof-forge.output.v1`) and optionally performs an **explicit opt-in Solana Devnet** transfer
call against an **operator-deployed** program id.

This is **not** formal evidence, **not** hermetic, **not** mainnet, and **not** a deployment tool.
ProofForge does **not** provide deploy, network registry, or key custody.

## What it does

| Subcommand | Network | Purpose |
|---|---|---|
| `verify-artifacts` | **Offline only** | Exact disk closure + domain digests + TransferSol ABI joins |
| `devnet-call` | **Explicit only** | Devnet genesis, Loader V3 ELF bind, ephemeral airdrop, one send, receipt |

### Artifact authority (`verify-artifacts`)

- Schema `proof-forge.output.v1` with **exact 14-key** `deny_unknown_fields` manifest
- Six manifest leaves + `manifest.json` + `evidence.json` exact closure
- Root must be a **real directory** (not a symlink); stable lstat before/after scan
- Every entry: regular file, **single hard-link** (Unix `nlink==1`), UTF-8 name; each leaf is opened with `O_NOFOLLOW`, descriptor/path identity is joined, and the read itself is capped
- Hard caps: ≤1024 entries, ≤64 MiB/read, ≤64 MiB/file, ≤256 MiB total
- Descriptor exact 4 keys; canonical leaf order:
  `bindings → ir → plan → idl → .s → .so` (roles `materialized-base`×5 + `finalized-extra`)
- Bare digests: **strict lowercase 64-hex** (no case folding)
- Evidence exact 5 keys `{target,sourceHash,semanticHash,deployable,note}`; identity joins
  manifest; note must carry structured active `profileDigest` / `catalogDigest` /
  `planDigest` / `irDigest` and **rejects preactivation** markers
- Recomputed digests:
  - `planDigest = SHA256("pf.solana.cpi-plan.v1" || 0x00 || plan bytes)`
  - `bindings.irDigest = SHA256("pf.solana.cpi-product-ir.v1" || 0x00 || IR bytes)`
  - `outputSetDigest` via `pf.output-set.engineering.v1` length-framed preimage
    (schema/target/profile/name/fileCount/descriptors/source/semantic/registry/support/build/plan/deployable/evidence)
- ABI joins: sole handler0, 16-byte outer (`probe16`), roles payer(w+s)/recipient(w)/System(ro),
  system-v1 codec `02000000`+`uint64Le`, exact runtimeNative binding pin, IR top keys, UTF-8
  assembly with invoke + set_return_data, ELF `7fELF`
- Critical JSON **duplicate keys fail closed**
- **`sourceHash` is not CLI-overridable** — frozen policy pin of tracked
  `Examples/TransferSol.lean` (`1fc319e8…5e29`)
- This proves an exact self-consistent engineering OutputSet shape, **not** signed provenance,
  source recompilation, or formal/hermetic attestation

### Devnet call state machine (`devnet-call`)

- Requires `--artifact-dir` and public `--program-id`
- Strict Devnet genesis `EtWTRABZaYq6iMfeYKouRu166VU2xqa1wcaWoxPkrZBG`
- Process-local **ephemeral** payer/recipient only (secret flags rejected)
- **Never prints private keys**; **never prints full RPC URL** (tokens redacted to
  `scheme://host[:port]/<redacted>`)
- `get_latest_blockhash_with_commitment(confirmed)` → retain `(Hash, lastValidBlockHeight)`
- After sign, **before any send**, stderr emits public facts:
  `local_signature=…`, `recent_blockhash=…`, `lastValidBlockHeight=…`
- Fee estimate **first**, then fund `balance ≥ amount + fee` via bounded airdrop (≤2 SOL;
  faucet errors include airdrop signature; **no wallet fallback**); after funding, acquire a fresh
  `(blockhash,lastValidBlockHeight)` and create the final signature so faucet latency cannot stale it.
  The final receipt verifies payer delta with observed `meta.fee`; the estimate remains informational
- Recipient is a fresh unfunded key. Native System transfer credits its default-shaped writable
  account directly; a tracked product-ELF Mollusk regression fixes this zero-lamport behavior
- `send_transaction_with_config`: `skip_preflight=false`, `preflight_commitment=confirmed`,
  `max_retries=Some(0)` — **exactly one send**, no blind re-sign
- Any send error is treated as **ambiguous**; poll known local signature only
- Poll uses `getSignatureStatuses(searchTransactionHistory=true)` **and**
  `getBlockHeight(confirmed)` to distinguish:
  - confirmed (`err` null)
  - on-chain error
  - clean expiry (`height > lastValidBlockHeight` and null status)
  - present but unconfirmed status past LVBH → landed/ambiguous until wall deadline
  - wall-deadline ambiguous timeout while still valid

  Default wall deadline **120s** (CLI `--wall-deadline-secs`, 1..=300)
- Loader V3 re-bind pre-send and post-confirm (slot/ELF/authority drift → fail)
- Receipt joins **local signed L1 facts**: first signature, recentBlockhash, header (3 fields),
  ordered accountKeys, exact compiled outer ix, outer count = 1; balances by key lookup
  (payer must be index 0); exactly one inner group/instruction at outer index 0 with System
  accounts `[payer,recipient]` + exact 12-byte data; return encoding `base64`; retains signed
  tx base64 + SHA-256 (no private keys)

## Build TransferSol (operator)

From a ProofForge checkout:

```bash
# Tracked product source:
#   Examples/TransferSol.lean  (module Examples.TransferSol)
scripts/solana_transfer_sol_build.sh
# Output default: build/v2/solana-transfer-sol-product
# Override: PROOF_FORGE_TRANSFER_SOL_OUT=build/v2/my-out scripts/solana_transfer_sol_build.sh
```

Expected leaves (names fixed to program id `TransferSol`):

- `manifest.json`, `evidence.json`
- `TransferSol.cpi-bindings.json`, `TransferSol.cpi-ir.json`
- `TransferSol.cpi-plan.json`, `TransferSol.idl.json`
- `TransferSol.s`, `TransferSol.so` (`deployable=true`)

## Operator-owned deployment

ProofForge **materializes** ELF/OutputSet only. **You** deploy `TransferSol.so` to Devnet
(Loader V3) with your own tooling and keys. This client accepts only the public
`--program-id`.

## Build / test this client

```bash
cd clients/solana-transfer-sol
cargo test --locked
cargo clippy --locked --all-targets -- -D warnings
cargo build --locked --release
```

Offline tests construct minimal exact artifact trees with **real domain digests** in temp
dirs. They do **not** package a product `.so` fixture and do **not** open network sockets
for airdrop/send.

## Commands

### `verify-artifacts` (offline)

```bash
cargo run --locked -- verify-artifacts \
  --artifact-dir /path/to/TransferSol-out
```

No `--expected-source-hash` (rejected).

### `devnet-call` (explicit network)

```bash
cargo run --locked -- devnet-call \
  --artifact-dir /path/to/TransferSol-out \
  --program-id <BASE58_PROGRAM_ID> \
  --rpc-url https://api.devnet.solana.com \
  --lamports 1000 \
  --timeout-secs 30 \
  --wall-deadline-secs 120
```

## Security / maturity boundaries

| Claim | Status |
|---|---|
| Formal TASK/TST / hermetic Stage-0 | **No** |
| Mainnet | **No** (Devnet genesis enforced) |
| Deployment complete | **No** (operator-owned) |
| Key custody / wallet files | **Rejected** |
| RPC URL secrets in logs/receipt | **Redacted** |
| RPC honesty / fork safety | Endpoint-relative only |
| OutputSet provenance / signed attestation | **No**; exact engineering self-consistency only |
| Upgrade authority TOCTOU | Documented; re-bind around send |

## Dependency pins

Uses empirically locked `solana-rpc-client = =4.1.2` modular pins and
`solana-loader-v3-interface = =7.0.0` (matches the 4.1.2 graph; no 6+7 dual).
Loader V3 account + confirmed-tx receipt paths use **raw reqwest JSON-RPC** where needed.
**Do not** relax pins to alpha crates.

## License

Apache-2.0
