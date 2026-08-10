# `pf` — ProofForge developer CLI

Cargo-like project workflow around `proof-forge-next` and official chain tools.
Does **not** reimplement the compiler.

## 30 seconds (project flow)

```bash
just pf-cli-build
export PROOF_FORGE_CLI="$PWD/.lake/build/bin/proof-forge-next"
PF="$PWD/clients/pf-cli/target/release/pf"

"$PF" new hello --target aleo
cd hello
"$PF" build                         # → build/aleo/
"$PF" run -- initialize 5u64
"$PF" deploy                        # save-only testnet tx
```

### Solana (same short path)

```bash
"$PF" new counter --target solana
cd counter
"$PF" build                         # → build/solana/
"$PF" test                          # Mollusk StateCell-shaped (any name)
"$PF" deploy                        # save-only package
# optional local validator/surfpool:
# "$PF" deploy --broadcast --network local --endpoint http://127.0.0.1:8899
```

### EVM

```bash
"$PF" new cell --target evm
cd cell
"$PF" build                         # → build/evm/
"$PF" test                          # local Anvil
"$PF" deploy                        # save-only → build/evm/tx/*.package.json
# optional local broadcast (Anvil default key #0 if no --private-key-env):
# "$PF" deploy --broadcast --network local
```

No monorepo long paths in the happy path.  
`pf build Examples/….lean --module … -o …` is **only** for maintainers / CI fixtures.

## Commands

| Command | Purpose |
|---|---|
| `pf new <name> [--target aleo\|solana\|evm]` | Scaffold (`pf.toml` + StateCell-shaped program) |
| `pf build` | Build default target → `build/<target>/` |
| `pf build -t solana` | One-shot other target (still short inside a project) |
| `pf clean` | Remove configured `out-dir` |
| `pf check` | Validate without writing artifacts |
| `pf run -- <fn> …` | Local run (**Aleo**); quiet by default, `-v` full Leo log |
| `pf inspect` | Validate artifact dir |
| `pf test` | Local runtime from `pf.toml` target |
| `pf test -t solana` | Mollusk StateCell-shaped（通用）；TransferSol = CPI 专项 |
| `pf test -t evm` | Anvil |
| `pf test -t evm,solana` | **D8** 多 target 顺序 + 统一 report（任一 fail → 非零） |
| `pf test -t aleo` | Leo smoke `initialize(0)` 或 skip（无 leo） |
| `pf verify -t solana` | Offline OutputSet joins |
| `pf deploy` | **Aleo / EVM / Solana**：默认 save-only package；`--broadcast` 仅 local |
| `pf execute` | Aleo execute save-only |
| `pf setup [--target] [-y]` | Checklist + 可选 compiler install |
| `pf doctor` / `pf version` / `pf list-targets` | Toolchain |

Install / dist: [`INSTALL.md`](./INSTALL.md) · `just pf-cli-dist`  
crates.io publish: [`PUBLISH.md`](./PUBLISH.md) · `cargo install proof-forge-pf` (binary name `pf`; still needs `proof-forge-next`)

Smoke (host-optional): `just pf-cli-smoke`

## What is “generic”?

| Surface | Generic? | Notes |
|---|---|---|
| `pf new` template | **Yes** — StateCell-shaped (`init` / `increment` / `get`, UInt64 `count`) | Program **name** is yours (`Hello`, `Counter`, …) |
| `pf build` | **Yes** — any project with `pf.toml` | Reads source/module/target from config |
| `pf test -t solana` | **Yes** for StateCell-shaped | Mollusk matrix is shape-based, not name-pinned |
| `pf test -t solana` + TransferSol | **Specialty** CPI gold | Auto-detected when `TransferSol.so` present |
| `pf verify -t solana` | Offline joins | Some generic CPI trees may fail `irDigest` note join today (FC); TransferSol is the client gold sample |
| `pf test -t evm` | **Yes** for StateCell-shaped `*.bin` | Prefers `StateCell.bin`, else first `*.bin` |

## Dependency model (important)

```text
your project (pf.toml + src/*.lean)
        │
        ▼  pf build
proof-forge-next   ← real dependency (compiler binary)
        │
        ▼
build/<target>/
```

| Dependency | Declared as | Resolved by |
|---|---|---|
| Compiler | `[dependencies] compiler = "proof-forge-next"` | `PROOF_FORGE_CLI` or `[toolchain].compiler-path` |
| Language gate | `[dependencies] language = "ProofForgeV2"` | source must contain `import ProofForgeV2` |
| Host SDK (optional) | *not in pf.toml* | agents/scripts only |

## Defaults

| Setting | Default | Override |
|---|---|---|
| target | `aleo` (`pf.toml`) | `-t` / `PF_TARGET` |
| output | `build/<target>/` | `-o` |
| network | `testnet` | `-n` / `PF_NETWORK` |
| source/module | from `pf.toml` | monorepo long form only when no project |

## Environment

| Variable | Purpose |
|---|---|
| `PROOF_FORGE_CLI` | `proof-forge-next` path |
| `PROOF_FORGE_ROOT` | monorepo root (scripts / doctor) |
| `PROOF_FORGE_TOOL_ROOT` | locked anvil/cast/sbpf |
| `PROOF_FORGE_SOLANA_CLIENT` | offline verify binary |
| `PROOF_FORGE_ALEO_LEO` | Leo override |
| `PF_TARGET` / `PF_NETWORK` | defaults |

## Safety

- Deploy/execute **save-only** unless `--broadcast`
- Mainnet refused in v0
- Broadcast needs `--private-key-env`; well-known Leo dev key refused
- Never rewrites compiler `deployable`
- Not formal / hermetic / mainnet evidence

## Spec

- ADR-0037, `docs/specs/cli-developer.md`
