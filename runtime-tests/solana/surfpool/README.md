# Surfpool local chain lane (engineering)

Host-optional **local Surfnet** for ProofForge Solana product ELFs.
Drop-in replacement path for `solana-test-validator`: start a local RPC, deploy
a product `.so`, and smoke-check it.

| Claim | Status |
|---|---|
| Local RPC (`getHealth`) | **yes** — `surfpool start --offline` |
| Deploy product ELF (`solana program deploy`) | **yes** — MiniAmmAssets |
| Full multi-role Token CPI business matrix | **yes** — `just solana-surfpool-miniamm-business` (mainnet fork for Token/ATA) |
| Mainnet / formal / hermetic | **no** |

Same product source as dual-chain M5: `Examples/MiniAmmAssets.lean`
(EVM Anvil + Solana Mollusk + this Surfpool deploy smoke).

## Prerequisites

- `surfpool` **≥ 1.5** on `PATH` (official installer → `~/.local/bin`;
  scripts prefer that over a stale `~/.cargo/bin/surfpool` 0.10.x):
  `curl -sL https://run.surfpool.run/ | bash`
- Solana CLI **4.x** matching Surfpool core (1.5.0 embeds `solana-core 4.1.2`):
  `sh -c "$(curl -sSfL https://release.anza.xyz/v4.1.2/install)"`
  CLI 3.x cannot deploy ProofForge SBPFv3 product ELFs.
- Product CLI: `lake build proof_forge_next`
- Locked `sbpf` under `PROOF_FORGE_TOOL_ROOT` (or default tool-root)

Scripts enable the Surfpool SBPFv3 feature gate
(`5cC3foj77CWun58pC51ebHFUWavHWKarWyR5UUik7dnC`) on start.

## Quick start

```bash
# Deploy-only smoke (offline Surfnet)
just solana-surfpool-miniamm-smoke

# Full business matrix (mainnet fork for classic Token/ATA + CPI):
#   initialize → addLiquidity → swap0to1 → slippage hold → removeLiquidity
just solana-surfpool-miniamm-business

# Or leave the chain up for manual casting:
just solana-surfpool-up          # prints RPC URL; writes pid under this dir
solana config set --url "$(cat runtime-tests/solana/surfpool/rpc-url.txt)"
# … deploy / send …
just solana-surfpool-down
```

## Layout

| Path | Role |
|---|---|
| `keys/` | **gitignored** ephemeral payer + program keypairs (generated on first run) |
| `rpc-url.txt` | Written by `solana-surfpool-up` |
| `pid` | Surfpool process id |
| `deployed.json` | Last deploy-only smoke record |
| `runner/` | Rust RPC business runner (`pf-surfpool-miniamm-business`) |

## Honesty

- Engineering local tooling only — **not** formal TASK-D5, hermetic Stage-0, or
  mainnet deployment evidence.
- Deploy-only smoke defaults to `--offline`. Business matrix defaults to
  `SURFPOOL_NETWORK=mainnet` so classic Token/ATA program ids exist for CPI.
- Mollusk `miniamm_assets` remains the ordinary host-optional differential gate
  (no network). Surfpool is the optional “real local chain” path.
- Keypairs under `keys/` are local throwaways; never reuse as production custody.
