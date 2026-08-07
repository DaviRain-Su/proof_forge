# Surfpool local chain lane (engineering)

Host-optional **local Surfnet** for ProofForge Solana product ELFs.
Drop-in replacement path for `solana-test-validator`: start a local RPC, deploy
a product `.so`, and smoke-check it.

| Claim | Status |
|---|---|
| Local RPC (`getHealth`) | **yes** — `surfpool start --offline` |
| Deploy product ELF (`solana program deploy`) | **yes** — MiniAmmAssets default |
| Full multi-role Token CPI invoke | **not this lane** — use Mollusk `miniamm_assets` |
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
# One-shot: start Surfpool → build MiniAmmAssets → deploy → program show → stop
just solana-surfpool-miniamm-smoke

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
| `deployed.json` | Last smoke deploy record (program id, signature, artifact path) |

## Honesty

- This is **engineering local tooling**, not a substitute for Mollusk differential
  gates and **not** mainnet deployment evidence.
- Default smoke uses `--offline` (no remote fork). Token/ATA CPI against real
  classic programs still needs mainnet-fork mode or vendored loaders — keep that
  on Mollusk until a dedicated fork+invoke suite is added.
- Keypairs under `keys/` are local throwaways; never reuse as production custody.
