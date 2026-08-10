# `pf` — ProofForge developer CLI

Cargo-like project workflow around `proof-forge-next` and official chain tools.
Does **not** reimplement the compiler.

## 30 seconds

```bash
just pf-cli-build
export PROOF_FORGE_CLI="$PWD/.lake/build/bin/proof-forge-next"
PF="$PWD/clients/pf-cli/target/release/pf"

# 1) new project (writes pf.toml + src template)
"$PF" new hello --target aleo
cd hello

# 2) build → build/aleo/  (default target from pf.toml)
"$PF" build

# 3) local VM (Aleo)
"$PF" run -- initialize 5u64
"$PF" run -- increment 3u64

# 4) network tx save-only (testnet default)
"$PF" deploy
"$PF" execute -- initialize 5u64
```

## Commands

| Command | Purpose |
|---|---|
| `pf new <name>` | Scaffold project (`pf.toml` + StateCell-shaped program) |
| `pf build` | Build default target → `build/<target>/` |
| `pf build -t solana` | Build a specific target → `build/solana/` |
| `pf check` | Validate without writing artifacts |
| `pf run -- <fn> …` | Local run (Aleo) using last build |
| `pf inspect` | Validate artifact dir |
| `pf deploy` / `pf execute` | Save network txs (no broadcast by default) |
| `pf doctor` / `pf setup` | Toolchain status |
| `pf list-targets` | Implemented targets from compiler |
| `pf version` | pf + compiler path + leo |

## Defaults (like Cargo)

| Setting | Default | Override |
|---|---|---|
| target | `aleo` (`pf.toml` `[build].default-target`) | `-t` / `--target` / `PF_TARGET` |
| output | `build/<target>/` | `-o` / `--output` |
| network | `testnet` | `-n` / `--network` / `PF_NETWORK` |
| source/module | from `pf.toml` | positional source + `--module` |

Example `pf.toml`:

```toml
[package]
name = "hello"
module = "Hello"
source = "src/Hello.lean"

[build]
default-target = "aleo"
out-dir = "build"

[network]
default = "testnet"
```

## Environment

| Variable | Purpose |
|---|---|
| `PROOF_FORGE_CLI` | `proof-forge-next` path |
| `PROOF_FORGE_ROOT` | monorepo root (optional) |
| `PROOF_FORGE_TOOL_ROOT` | locked tools |
| `PROOF_FORGE_ALEO_LEO` | Leo override |
| `PF_TARGET` / `PF_NETWORK` | default target/network |

## Safety

- Deploy/execute are **save-only** unless `--broadcast`
- Mainnet refused in v0
- Broadcast needs `--private-key-env`; well-known Leo dev key refused
- Never rewrites compiler `deployable`
- Not formal / hermetic / mainnet evidence

## Spec

- ADR-0037, `docs/specs/cli-developer.md`
