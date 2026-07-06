# AGENTS.md

## Cursor Cloud specific instructions

ProofForge is a Lean 4 compiler/CLI (`proof-forge`) that lowers Lean smart-contract
sources to portable IR and target artifacts. Implemented backends live on `main`:
`evm` (Lean → portable IR → Yul → `solc` → bytecode, validated by Foundry + Anvil),
`solana-sbpf-asm` (portable IR → sBPF assembly → ELF, validated by Mollusk + Pinocchio
equivalence), `wasm-near` (portable IR → Wasm AST → WAT → `wat2wasm`), `move-sui`
(Counter MVP, local `sui move build/test`), `psy-dpn` (`.psy` → Dargo), plus research
spikes `aleo-leo` and `wasm-cloudflare-workers`. See README "Backend Status" for the
full stage table. Default CI runs the EVM, Solana-light, NEAR, and Psy static gates;
Solana live-network/Pinocchio gates and `just psy-all` need extra tools (see below).

### Toolchain (already installed in the VM snapshot)
- `lean`/`lake` come from `elan`; the version is pinned by `lean-toolchain`. A VM-snapshot
  startup script (not in this repo) runs `elan toolchain install "$(cat lean-toolchain)"`
  idempotently; if a toolchain is missing, run that command yourself.
- `just` (command runner), `solc` (0.8.30), Foundry (`forge`/`cast`/`anvil`), `wat2wasm`
  (wabt), and Rust/Cargo are installed and on `PATH` via `~/.bashrc`. If a non-interactive
  shell lacks them, add `$HOME/.elan/bin`, `$HOME/.local/bin`, and `$HOME/.foundry/bin`
  to `PATH`. `sui`, `leo`, `wrangler`, and Solana SBF/Surfpool tooling are NOT installed
  here; gates that need them skip or live in separate CI jobs.

### Codeberg remote and CI
- Git remote: `git@codeberg.org:davirain/proof_forge.git` (`codeberg`).
- Hosted CI uses Codeberg Woodpecker (`ci.codeberg.org`); pipeline config is `.woodpecker.yml`
  and runs `just check` after `scripts/ci/woodpecker-setup.sh`. Enable the repo once at
  https://ci.codeberg.org/repos/add after Woodpecker access is approved.

### Build / lint / test / run
The root `justfile` is the canonical command catalog (`just --list`). It is also the CI
entrypoint (see `.woodpecker.yml` on Codeberg and `.github/workflows/ci.yml` on GitHub). Key commands:
- Build: `just build` (`lake build`).
- Fast baseline (Lean + EVM + Solana-light + NEAR + Psy static gates + testkit + docs
  + SDK schema + CLI gates): `just check`. This is the closest local mirror of the
  GitHub `build-test` job's static subset.
- Full EVM gates (compile examples, Foundry runtime smoke, live Anvil deploy,
  dynamic constructor Anvil, broadcast gas flags): `just evm-all`.
- `just ci` is a local CI-flavored aggregate, not a strict subset of the GitHub
  `build-test` job. It omits `contract-spec-json`, `contract-client`, the NEAR
  diagnostic/IR-coverage smokes, `Tests/IROwnership.lean`, the formal-semantics
  anchors (`ProofForge.Backend.Evm.Refinement`, `ValueVaultInvariant`,
  `Tests/NearWasmFormal.lean`), `emitwat-ci-smoke`, `near-target-first`,
  `contract-source-diagnostics`, and `psy-metadata*`; and it adds `evm-broadcast-smoke`
  and `evm-mixin-compose` via `evm-all`. To fully reproduce the `build-test` job, run
  its steps individually as listed in `.github/workflows/ci.yml`. `sdk-schema`,
  `cli-deploy`, and `cli-check` live in `just check` but are not in the `build-test`
  job.
- Run the CLI directly, e.g. compile a Lean contract to EVM runtime bytecode:
  `lake env proof-forge build --target evm --root . --module contract -o build/evm/Counter.bin Examples/Evm/Contracts/Counter.lean`

### Non-obvious caveats
- Lean commands must be run through `lake env ...` so the toolchain env is set (e.g.
  `lake env proof-forge ...`, `lake env lean --run Tests/Foo.lean`).
- `just evm-all` / `just evm-anvil-deploy` start their own local Anvil instance; no
  external RPC or funded key is required.
- Solana `*-web3`/live Pinocchio gates and `just psy-all` (Dargo-backed Psy smokes)
  require extra tools not installed here (`surfpool`/Node web3 deps, `dargo`, Solana
  SBF platform-tools). They are outside the default `just check` path; the Lean-only
  Solana gates (`just solana-light`) and Psy static gates (`psy-diagnostics`,
  `psy-coverage`, `psy-metadata*`) *are* in `just check` and the `build-test` CI job.
  Skip the live-network gates unless explicitly requested.
- Build outputs go to `build/` and `.lake/` (both git-ignored); safe to delete to force a
  clean rebuild.
