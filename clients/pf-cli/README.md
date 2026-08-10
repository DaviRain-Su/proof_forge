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

### Solana offline verify (D7a)

```bash
export PROOF_FORGE_SOLANA_CLIENT="$PWD/clients/solana-client/target/release/proof-forge-solana-client"
# monorepo fixture (TransferSol is the gold sample)
"$PF" build Examples/TransferSol.lean --module Examples.TransferSol -t solana -o build/v2/ts
"$PF" verify -t solana --artifact build/v2/ts
"$PF" verify -t solana --artifact build/v2/ts --adapter transfer-sol-v1
```

### EVM local Anvil test (D7c)

```bash
export PROOF_FORGE_TOOL_ROOT="$HOME/.cache/proof-forge-v2/tool-root/darwin-arm64"  # locked anvil+cast
"$PF" build Examples/StateCell.lean --module Examples.StateCell -t evm -o build/v2/sc-evm
"$PF" test -t evm --artifact build/v2/sc-evm
# or: just pf-cli-evm-test
```

## Commands

| Command | Purpose |
|---|---|
| `pf new <name>` | Scaffold project (`pf.toml` + StateCell-shaped program) |
| `pf build` | Build default target → `build/<target>/` |
| `pf build -t solana` | Build a specific target → `build/solana/` |
| `pf clean` | Remove configured `out-dir` (default `build/`) |
| `pf check` | Validate without writing artifacts |
| `pf run -- <fn> …` | Local run (Aleo); quiet by default, `-v` full Leo log |
| `pf inspect` | Validate artifact dir |
| `pf verify -t solana` | Offline Solana OutputSet verify (`proof-forge-solana-client`) |
| `pf verify -t solana --adapter transfer-sol-v1` | + TransferSol program pins |
| `pf test -t evm` | Local Anvil deploy+call matrix (`scripts/pf_evm_test.sh`) |
| `pf deploy` / `pf execute` | Save network txs (Aleo; no broadcast by default) |
| `pf doctor` / `pf setup` | Toolchain status |
| `pf list-targets` | Implemented targets from compiler |
| `pf version` | pf + compiler path + leo |

Smoke (host-optional): `just pf-cli-smoke`

## Dependency model (important)

This is **not** a Lake/`cargo` library project. You do **not** put ProofForge in
`lake-packages` or crates.io.

```text
your project (pf.toml + src/*.lean)
        │
        ▼  pf build
proof-forge-next   ← real dependency (compiler binary)
        │
        ▼
build/<target>/    (.aleo / other artifacts)
```

| Dependency | Declared as | Resolved by |
|---|---|---|
| Compiler | `[dependencies] compiler = "proof-forge-next"` | `PROOF_FORGE_CLI` or `[toolchain].compiler-path` |
| Language gate | `[dependencies] language = "ProofForgeV2"` | source must contain `import ProofForgeV2` |
| Host SDK (optional) | *not in pf.toml* | `pip install proof-forge-sdk` for agents only |

`import ProofForgeV2` is a **product source-gate string**, not a Lake import graph edge.

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

[dependencies]
compiler = "proof-forge-next"
language = "ProofForgeV2"

[toolchain]
channel = "stable"
# compiler-path = "/abs/path/to/proof-forge-next"

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
| `PROOF_FORGE_SOLANA_CLIENT` | `proof-forge-solana-client` for `pf verify -t solana` |
| `PF_TARGET` / `PF_NETWORK` | default target/network |

## Safety

- Deploy/execute are **save-only** unless `--broadcast`
- Mainnet refused in v0
- Broadcast needs `--private-key-env`; well-known Leo dev key refused
- Never rewrites compiler `deployable`
- Not formal / hermetic / mainnet evidence

## Spec

- ADR-0037, `docs/specs/cli-developer.md`
