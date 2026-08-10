# `pf` runtime architecture — why crates.io feels “wrong”

## One-sentence truth

**`proof-forge-pf` on crates.io is only the developer orchestrator.**  
It does **not** contain the compiler, Solana verifier, Mollusk harness, or Anvil scripts.

If you only `cargo install proof-forge-pf`, many commands will correctly refuse until you supply external tools.

## Layers (do not collapse them)

```text
┌─────────────────────────────────────────────────────────────┐
│  A. crates.io binary: pf  (proof-forge-pf)                    │
│     - clap UX, pf.toml, safety gates                         │
│     - spawns other tools; never re-compiles ProgramV1        │
└───────────────────────────┬─────────────────────────────────┘
                            │ spawn
┌───────────────────────────▼─────────────────────────────────┐
│  B. Compiler product: proof-forge-next                       │
│     - Lean/Lake build; OutputSet authority                   │
│     - NOT on crates.io (use Release / monorepo lake build)   │
│     env: PROOF_FORGE_CLI                                     │
└───────────────────────────┬─────────────────────────────────┘
                            │ artifacts
┌───────────────────────────▼─────────────────────────────────┐
│  C. Chain host tools (optional per command)                  │
│     Aleo:  leo                                               │
│     EVM:   anvil, cast   (PROOF_FORGE_TOOL_ROOT / PATH)      │
│     Solana build: sbpf   (PROOF_FORGE_TOOL_ROOT)             │
│     Solana local deploy: solana CLI                          │
└───────────────────────────┬─────────────────────────────────┘
                            │ some commands only
┌───────────────────────────▼─────────────────────────────────┐
│  D. Monorepo / contributor-only companions                   │
│     proof-forge-solana-client   → pf verify -t solana        │
│     scripts/pf_evm_test.sh      → pf test -t evm (today)     │
│     scripts/pf_solana_test.sh   → pf test -t solana (today)  │
│     runtime-tests/solana        → Mollusk cargo tests        │
│     env: PROOF_FORGE_ROOT, PROOF_FORGE_SOLANA_CLIENT, …       │
└─────────────────────────────────────────────────────────────┘
```

## Command × what it needs

| Command | crates.io `pf` alone | + `proof-forge-next` | + host tools | + monorepo D |
|---|---|---|---|---|
| `pf new` / `pf --help` | ✅ | | | |
| `pf build` / `pf check` | | ✅ | sbpf for solana finalize | |
| `pf run` (aleo) | | ✅ | leo | |
| `pf deploy` aleo save | | ✅ | leo | |
| `pf deploy` evm save | | ✅ | | |
| `pf deploy` evm `--broadcast --network local` | | ✅ | anvil+cast | |
| `pf deploy` solana save | | ✅ | | |
| `pf deploy` solana local broadcast | | ✅ | solana CLI + local RPC | |
| `pf verify -t solana` | | ✅ | | **solana-client binary** |
| `pf test -t evm` | | ✅ | anvil+cast | **scripts/pf_evm_test.sh** (today) |
| `pf test -t solana` | | ✅ | cargo | **scripts + runtime-tests** (today) |

## Why Solana Client is separate (this is intentional)

`clients/solana-client` is an **offline OutputSet verifier**, same spirit as ADR-0037:

- does **not** live inside the Lean compiler
- does **not** do RPC/deploy
- is a second binary: `proof-forge-solana-client`

`pf verify` only **spawns** it. That is the same pattern as spawning `leo` / `cast`.

What feels wrong is not the split — it is that **crates.io does not install that companion**, while monorepo just recipes do.

### Intended long-term product shapes

1. **Release bundle** (recommended): `pf` + `proof-forge-next` (+ optional `proof-forge-solana-client`) side-by-side  
2. **crates.io**: orchestrator only — always document external deps  
3. **Later (optional)**: publish `proof-forge-solana-client` as its own crate; `pf` resolves PATH/sibling  

We should **not** vendor Mollusk + Agave into the `pf` crate — that would explode deps and blur offline verify vs runtime test.

## Why `pf test` shells out to bash scripts today

Historical path while D7 shipped fast:

- EVM matrix lived in `scripts/pf_evm_test.sh`
- Solana Mollusk lived in `runtime-tests/solana` + `scripts/pf_solana_test.sh`

That means **`pf test` is monorepo-oriented today**.  
Standalone `cargo install` users get a clear error pointing at Release/monorepo — not a silent half-pass.

### Target end-state (honest roadmap)

| Feature | Standalone path |
|---|---|
| `pf test -t evm` | Prefer pure Rust spawn of anvil/cast (already partly in `deploy`); shrink bash |
| `pf test -t solana` | Either document monorepo-only, or ship a small `pf-solana-mollusk` binary later |
| `pf verify -t solana` | `cargo install proof-forge-solana-client` (future) or bundle in Release |

## Env cheat-sheet

| Env | Purpose |
|---|---|
| `PROOF_FORGE_CLI` | path to `proof-forge-next` |
| `PROOF_FORGE_ROOT` | monorepo root (scripts / doctor install) |
| `PROOF_FORGE_TOOL_ROOT` | locked anvil/cast/sbpf |
| `PROOF_FORGE_SOLANA_CLIENT` | offline verifier binary |
| `PROOF_FORGE_ALEO_LEO` | Leo override |
| `PROOF_FORGE_EVM_TEST_SCRIPT` | override Anvil test script |
| `PROOF_FORGE_SOLANA_TEST_SCRIPT` | override Mollusk test script |

## What to tell crates.io users

```bash
cargo install proof-forge-pf --locked   # only the shell
# Still required for real work:
export PROOF_FORGE_CLI=/path/to/proof-forge-next

pf setup --target aleo     # checklist
pf new hello && cd hello && pf build   # needs compiler

# These need MORE than crates.io:
pf verify -t solana        # needs proof-forge-solana-client
pf test -t solana          # needs monorepo scripts + runtime-tests (today)
pf test -t evm             # needs monorepo script + anvil (today)
```

Prefer **`just pf-cli-dist` / GitHub Release** if you want “download and run” without cloning.
