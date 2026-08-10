# Install `pf` (developer CLI) — external authors first

`pf` is a **thin orchestrator**. The real compiler is `proof-forge-next`.
**External authors never need `lake build`.** See ADR-0040 /
`docs/product/14-external-author-mvp.md`.

## Recommended (external author): bundle → setup → work

```bash
# 1) Get engineering-dist bundle (GitHub Release asset)
#    proof-forge-bundle-<ver>-linux-x86_64.tar.gz  (or darwin-arm64)

bash scripts/install.sh --from proof-forge-bundle-*.tar.gz
# or: pf bootstrap --from proof-forge-bundle-*.tar.gz

export PATH="$HOME/.local/proof-forge/current/bin:$PATH"
export PROOF_FORGE_CLI="$HOME/.local/proof-forge/current/bin/proof-forge-next"
export PROOF_FORGE_ROOT="$HOME/.local/proof-forge/current"
# hostMode defaults to dev (no hermetic host:stat pin)

pf version
pf -y setup --target evm          # installs Tool Lock solc via proof-forge-next install
pf new hello --target evm && cd hello
pf build
```

## Alternative: crates.io orchestrator only

```bash
cargo install proof-forge-pf --locked          # binary name: pf  (version == VERSION)
# still need the compiler from a Release bundle:
pf bootstrap --from /path/to/proof-forge-bundle-*.tar.gz
pf -y setup --target aleo
```

### What each crates.io package is

| Install | Binary | Role |
|---|---|---|
| `cargo install proof-forge-pf` | `pf` | developer UX / orchestrator |
| `cargo install proof-forge-solana-client` | `proof-forge-solana-client` | offline `pf verify -t solana` |

Still **not** on crates.io: `proof-forge-next` (compiler), Mollusk harness, Foundry lock.

`pf setup` is the source of truth for missing pieces + install commands.

Full map: [`ARCHITECTURE.md`](./ARCHITECTURE.md).

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
