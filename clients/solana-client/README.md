# proof-forge-solana-client

Offline engineering verifier for ProofForge Solana product OutputSets
(`proof-forge.output.v1`). It has **no RPC, Devnet, faucet, wallet, signing, deployment, or
network-write surface**.

Executable behavior for product fixtures is tested locally by loading the manifest-bound product
ELF into Mollusk and invoking the native System Program. No test SOL or public Program ID is
required.

## Surfaces

| Surface | Network | Purpose |
|---|---|---|
| `verify-artifacts` | None | Exact disk closure, domain digests, and profile/program ABI joins |
| Optional program adapter | None | Fixture-specific pins (e.g. TransferSol sourceHash + handler/ABI) |

## Artifact authority

`verify-artifacts` enforces:

- exact 14-key `proof-forge.output.v1` manifest and five-key evidence sidecar;
- closed roles (`materialized-base` / `finalized-extra`) in canonical role/path order;
- real non-symlink root and regular single-link leaves;
- `O_NOFOLLOW` leaf opens, descriptor/path identity joins, and bounded reads;
- raw leaf/evidence SHA-256 and domain-separated Plan/IR/output-set digests;
- closed current profile IDs (`solana-sbpf-plan-v1`, `solana-sbpf-elf-v1`,
  `solana-sbpf-cpi-elf-v1`); unknown profiles fail closed;
- dynamic `{programName}` leaf shapes per profile (no hardcoded TransferSol filenames).

Optional `--program-adapter transfer-sol-v1` adds the frozen TransferSol sourceHash pin and
exact handler/accounts/System CPI/codec/IR/assembly checks. Without an adapter, any legal
current-profile OutputSet is verified as engineering self-consistency only.

This is engineering self-consistency, **not** signed provenance, source recompilation, formal
proof, or hermetic attestation.

## Extension model

The binary is intentionally program-neutral. Its verification path is layered as:

1. `output_set` — target-wide manifest/evidence/filesystem/digest checks;
2. `profile` — closed dispatch for a registered Solana codegen profile;
3. `program_adapter` — optional program-specific ABI/source pins.

Add future Solana programs as new `program_adapter` IDs and tests rather than creating another CLI.
A future local or operator-owned invocation transport can consume the same verified profile result;
this crate currently remains verify-only and does not silently introduce RPC, signing, deployment,
or wallet custody.

## Install

```bash
cargo install proof-forge-solana-client --locked
# used by: pf verify -t solana
# or: export PROOF_FORGE_SOLANA_CLIENT=$(which proof-forge-solana-client)
```

See [`PUBLISH.md`](./PUBLISH.md) for crates.io maintainers.

## Direct verifier command

```bash
# After install / monorepo release build:
proof-forge-solana-client verify-artifacts \
  --artifact-dir build/v2/solana-transfer-sol-product

# Optional TransferSol fixture pins:
proof-forge-solana-client verify-artifacts \
  --artifact-dir build/v2/solana-transfer-sol-product \
  --program-adapter transfer-sol-v1

# Monorepo dev:
cargo run --manifest-path clients/solana-client/Cargo.toml --locked -- \
  verify-artifacts --artifact-dir build/v2/solana-transfer-sol-product
```

The CLI intentionally rejects unknown `devnet-call`, `deploy`, `--rpc-url`, wallet, keypair, and
source-hash override surfaces because none are part of this client.

## Client development

```bash
cargo test --manifest-path clients/solana-client/Cargo.toml --locked
cargo clippy --manifest-path clients/solana-client/Cargo.toml \
  --locked --all-targets -- -D warnings
cargo build --manifest-path clients/solana-client/Cargo.toml --locked --release
```

## Boundaries

| Claim | Status |
|---|---|
| Network access / test token | **None required** |
| Deployment | **Not provided** |
| Wallet/key custody | **No surface** |
| Local executable behavior | Mollusk engineering runtime tests (product fixtures) |
| Formal TASK/TST / hermetic Stage-0 | **No** |
| Mainnet/Devnet completion | **No** |
| OutputSet provenance / signed attestation | **No** |

If an operator wants to deploy an ELF to a local validator, that remains an external local-tooling
step. ProofForge only materializes and verifies the product artifacts here.

## License

Apache-2.0
