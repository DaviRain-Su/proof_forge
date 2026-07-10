# Contributor Onboarding

This page is the shortest path from a clean checkout to a useful local
ProofForge development loop. It is intentionally practical: install the shared
tools first, run the smallest gates, then add target-specific tools only when
you work on that target.

## Current Product Focus

Gate P0 has closed for the primary-chain completion covenant (D-045). The three
priority targets completed their scoped P0 local/CI gates in this order:

1. `solana-sbpf-asm`
2. `evm`
3. `wasm-near`

All three remain `experimental` in the generated backend status. P0 records
artifact, execution, metadata, diagnostic, and budget evidence for documented
fragments; it does not claim universal compiler correctness or production
deployment readiness.

The next hardening lane is the CLI M3/M4 migration from legacy flags to
`proof-forge build|emit|check --target ...`. Tier-1 target work is eligible to
be scheduled, but should wait behind that cleanup unless a security or CI
maintenance issue takes priority.

## Required Tools

Install these for normal development:

- `elan`, using the repo-pinned `lean-toolchain`.
- `just`, which is the command catalog used by local development and CI.
- `python3`, used by docs and validation scripts.
- Rust/Cargo, used by the unified testkit and several target harnesses.

Recommended editor setup:

- VS Code or Cursor with the official `leanprover.lean4` extension.
- The repository includes `.vscode/extensions.json` and `.vscode/settings.json`
  so the Lean extension, TOML syntax, and low-noise search/watch exclusions are
  offered automatically.
- Scaffolded portable projects copy the same `.vscode` recommendations and
  `proof-forge check` task recipes.
- Open the repository root, not a subdirectory, so Lake, imports, and
  `lean-toolchain` resolve consistently.
- Let the extension use the repo toolchain through `elan`; do not override the
  Lean version per workspace.

## Starter Template

For the smallest authoring loop, start from the in-repository portable template:

```sh
lake env lean templates/portable-counter/Counter.lean
```

The template lives at
[templates/portable-counter](../templates/portable-counter/README.md). It uses
`ProofForge.Contract.Source` and does not import an EVM, Solana, or NEAR SDK.
Target selection belongs to CLI configuration (`--target evm`,
`--target solana-sbpf-asm`, `--target wasm-near`, ...). A standalone package
scaffold and arbitrary `contract_source` file routing through all target-first
`build` paths are still open DX/source-routing items; keep the template in-repo
until the public SDK/package boundary is stable.

## First Local Pass

```sh
elan show
lake build
just --list
just check
scripts/i18n/check-sync.sh
git diff --check
```

`just check` is the normal fast gate. It runs the common build, diagnostics,
coverage, and smoke slices that CI expects without requiring every live-chain
tool.

Use `proof-forge check --target <id> [--fixture <id>|input.lean]` to validate
capability support and lowering before building artifacts. Pass
`--report-format json` for machine-readable diagnostics suitable for editor
integration and smoke validators.

## Target-Specific Tools

Install these only when working on the matching target or gate:

| Target area | Tools |
|---|---|
| EVM | Foundry (`cast`, `forge`), `solc` |
| Solana | `sbpf`, Solana CLI, `solana-keygen`, Cargo for Rust live harnesses, Surfpool for live local tests; Node/npm only for generated JS client checks |
| Wasm/NEAR | `wat2wasm`; NEAR sandbox only for live deployment work |
| Psy/DPN | `psyup`, `dargo` |
| Aleo | `leo` |
| Cloudflare Workers | Node/npm, `wrangler` |

The authoritative command list and prerequisites are in
[validation-gates.md](validation-gates.md). If a tool is missing, many scripts
skip that optional branch and still validate the generated source, metadata, or
diagnostics.

## Working Rules

- Before changing code, read [development-standards.md](development-standards.md)
  and the nearest source-of-truth doc for the touched boundary.
- Keep English engineering docs authoritative. Chinese `.zh.md` translations
  are synchronized from the English docs on `main`.
- Public CLI flags, target ids, capability ids, artifact fields, validation
  commands, target lifecycle stages, or example behavior changes must update
  the matching docs in the same change.
- Run the narrow gate first, then `just check`, then broader target gates only
  when the change touches that target.
