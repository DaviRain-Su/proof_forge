# Install `pf` (developer CLI) — 30 seconds

`pf` is a **thin orchestrator**. The real compiler is `proof-forge-next`.
Install **both** on the same machine/path layout when possible.

## Option A — monorepo (contributors)

```bash
git clone <this-repo> && cd proof_forge
lake build proof_forge_next
cargo build --manifest-path clients/pf-cli/Cargo.toml --locked --release

export PROOF_FORGE_CLI="$PWD/.lake/build/bin/proof-forge-next"
export PATH="$PWD/clients/pf-cli/target/release:$PATH"

pf setup --target aleo
pf new hello --target aleo && cd hello
pf build
```

Optional chain tools (host):

| Target | Tools | Env |
|---|---|---|
| Aleo run/deploy | Leo 4.x | `PROOF_FORGE_ALEO_LEO` or PATH |
| EVM `pf test` | locked `anvil`+`cast` | `PROOF_FORGE_TOOL_ROOT` |
| Solana build | locked `sbpf` | `PROOF_FORGE_TOOL_ROOT` |
| Solana `pf verify` | `proof-forge-solana-client` | `PROOF_FORGE_SOLANA_CLIENT` |
| Solana `pf test` | `cargo` + `runtime-tests/solana` | monorepo / crate present |

## Option B — side-by-side binaries (release layout)

After a GitHub Release (or `just pf-cli-dist`):

```text
dist/pf-<os>-<arch>/
  pf
  proof-forge-next          # recommended sibling
  README.txt
  INSTALL.md
```

```bash
cd dist/pf-darwin-arm64
export PATH="$PWD:$PATH"
export PROOF_FORGE_CLI="$PWD/proof-forge-next"   # or rely on sibling resolution
pf version
pf setup --target solana
```

`pf` resolves the compiler in this order:

1. `PROOF_FORGE_CLI`
2. sibling `proof-forge-next` next to the `pf` binary
3. `$PROOF_FORGE_ROOT/.lake/build/bin/proof-forge-next`
4. cwd monorepo `.lake/build/bin/proof-forge-next`

## Option C — copy into a personal bin

```bash
mkdir -p "$HOME/.local/bin"
cp clients/pf-cli/target/release/pf "$HOME/.local/bin/"
cp .lake/build/bin/proof-forge-next "$HOME/.local/bin/"
export PATH="$HOME/.local/bin:$PATH"
export PROOF_FORGE_CLI="$HOME/.local/bin/proof-forge-next"
```

## Verify install

```bash
pf version
pf setup --target aleo          # checklist
pf new demo --target aleo && cd demo && pf build
```

## Safety / non-claims

- Not formal Stage-0 attestation
- Does not default-broadcast network txs
- Mainnet refused in v0
- `pf setup --yes` may call `proof-forge-next install` only when compiler + package root are known — it does **not** silently inject random PATH tools into the lock root

## See also

- `clients/pf-cli/README.md` — command surface
- `docs/specs/cli-developer.md` — contract
- `docs/adr/0037-developer-cli-pf.md` — architecture
