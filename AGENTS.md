# AGENTS.md

## Cursor Cloud specific instructions

ProofForge is a Lean 4 compiler/CLI (`proof-forge`) that lowers Lean smart-contract
sources to portable IR and target artifacts. The implemented backend is EVM (via Yul +
`solc` + Foundry); Solana/sBPF and Psy/DPN are additional emit paths, and many
Solana/Psy gates are live-network or `dargo`-backed and are not part of default CI.

### Toolchain (already installed in the VM snapshot)
- `lean`/`lake` come from `elan`; the version is pinned by `lean-toolchain`. The startup
  update script runs `elan toolchain install "$(cat lean-toolchain)"` (idempotent).
- `just` (command runner), `solc` (0.8.30), and Foundry (`forge`/`cast`/`anvil`) are
  installed and on `PATH` via `~/.bashrc`. If a non-interactive shell lacks them, add
  `$HOME/.elan/bin`, `$HOME/.local/bin`, and `$HOME/.foundry/bin` to `PATH`.

### Build / lint / test / run
The root `justfile` is the canonical command catalog (`just --list`). It is also the CI
entrypoint (see `.github/workflows/ci.yml`). Key commands:
- Build: `just build` (`lake build`).
- Fast baseline (lint + Lean/EVM/Psy/Quint static gates): `just check` (includes `just quint-mbt-gate` and `just quint-model-gate`; skips when `quint` or Java 17+ is missing locally).
- Full EVM gates (compile examples, Foundry runtime smoke, live Anvil deploy):
  `just evm-all`.
- Full CI sequence locally: `just ci`.
- Run the CLI directly, e.g. compile a Lean contract to EVM runtime bytecode:
  `lake env proof-forge build --target evm --root . --module contract -o build/evm/Counter.bin Examples/Evm/Contracts/Counter.lean`

### Non-obvious caveats
- Lean commands must be run through `lake env ...` so the toolchain env is set (e.g.
  `lake env proof-forge ...`, `lake env lean --run Tests/Foo.lean`).
- `just evm-all` / `just evm-anvil-deploy` start their own local Anvil instance; no
  external RPC or funded key is required.
- Solana `*-web3`/live gates and `just psy-all` require extra tools not installed here
  (`surfpool`/Node web3 deps, `dargo`, Solana SBF platform-tools). They are intentionally
  outside the default `just check` / CI path; skip them unless explicitly requested.
- Build outputs go to `build/` and `.lake/` (both git-ignored); safe to delete to force a
  clean rebuild.
