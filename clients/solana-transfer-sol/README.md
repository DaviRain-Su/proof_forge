# solana-transfer-sol

Offline engineering verifier for the ProofForge `TransferSol` product OutputSet
(`proof-forge.output.v1`). It has **no RPC, Devnet, faucet, wallet, signing, deployment, or
network-write surface**.

Executable behavior is tested locally by loading the manifest-bound product ELF into Mollusk and
invoking the native System Program. No test SOL or public Program ID is required.

## Surfaces

| Surface | Network | Purpose |
|---|---|---|
| `verify-artifacts` | None | Exact disk closure, domain digests, and TransferSol ABI joins |
| `just solana-transfer-sol-local` | None | Build + independent verification + eight focused tests (six execute the ELF) |

## Artifact authority

`verify-artifacts` enforces:

- exact 14-key `proof-forge.output.v1` manifest and five-key evidence sidecar;
- six manifest leaves plus `manifest.json` and `evidence.json`, with no extra files;
- real non-symlink root and regular single-link leaves;
- `O_NOFOLLOW` leaf opens, descriptor/path identity joins, and bounded reads;
- raw leaf/evidence SHA-256 and domain-separated Plan/IR/output-set digests;
- canonical leaf order: bindings, IR, Plan, IDL, assembly, ELF;
- frozen source hash for tracked `Examples/TransferSol.lean`;
- one handler (`transfer`, ID 0), exact 16-byte outer data, ordered
  payer(writable+signer)/recipient(writable)/System(readonly) roles;
- one `solana.system.transfer` CPI site with `02000000 || uint64Le(lamports)` codec;
- exact `system-v1` runtime-native binding, product markers, and ELF magic.

This is engineering self-consistency, **not** signed provenance, source recompilation, formal
proof, or hermetic attestation.

## Build and run locally

From the repository root:

```bash
# Build and inspect the ordinary product OutputSet.
just solana-transfer-sol-build

# Rebuild, then consume every product artifact with the independent Rust verifier.
just solana-transfer-sol-offline

# Rebuild + verify + run eight focused tests; six load and execute TransferSol.so.
just solana-transfer-sol-local
```

The local runtime matrix covers:

- exact product tree and ABI;
- successful System transfer and UInt64 return data;
- zero-lamport recipient credit;
- swapped account metas;
- missing payer signer;
- wrong System Program identity;
- underfunded payer rollback.

## Direct verifier command

```bash
cargo run --manifest-path clients/solana-transfer-sol/Cargo.toml --locked -- \
  verify-artifacts --artifact-dir build/v2/solana-transfer-sol-product
```

The CLI intentionally rejects unknown `devnet-call`, `deploy`, `--rpc-url`, wallet, keypair, and
source-hash override surfaces because none are part of this client.

## Client development

```bash
cargo test --manifest-path clients/solana-transfer-sol/Cargo.toml --locked
cargo clippy --manifest-path clients/solana-transfer-sol/Cargo.toml \
  --locked --all-targets -- -D warnings
cargo build --manifest-path clients/solana-transfer-sol/Cargo.toml --locked --release
```

## Product leaves

The default output directory is `build/v2/solana-transfer-sol-product`:

- `manifest.json`, `evidence.json`
- `TransferSol.cpi-bindings.json`, `TransferSol.cpi-ir.json`
- `TransferSol.cpi-plan.json`, `TransferSol.idl.json`
- `TransferSol.s`, `TransferSol.so`

## Boundaries

| Claim | Status |
|---|---|
| Network access / test token | **None required** |
| Deployment | **Not provided** |
| Wallet/key custody | **No surface** |
| Local executable behavior | Mollusk engineering runtime tests |
| Formal TASK/TST / hermetic Stage-0 | **No** |
| Mainnet/Devnet completion | **No** |
| OutputSet provenance / signed attestation | **No** |

If an operator wants to deploy the ELF to a local validator, that remains an external local-tooling
step. ProofForge only materializes and verifies the product artifacts here.

## License

Apache-2.0
