# Publishing `proof-forge-pf` (developer CLI `pf`)

## What crates.io can and cannot ship

| Artifact | crates.io? | Notes |
|---|---|---|
| `pf` binary (Rust orchestrator) | **Yes** — crate `proof-forge-pf` | `cargo install proof-forge-pf` |
| `proof-forge-next` (Lean compiler) | **No** | Lake / GitHub Release tarball |
| `proof-forge-solana-client` | **Not yet** | Separate crate/binary; monorepo or future publish |
| Mollusk `runtime-tests` + bash harness | **No** | Monorepo contributor path |
| Locked anvil/cast/sbpf/Leo | **No** | Host / Tool Lock |

**crates.io alone is not a full toolchain install.**  
See [`ARCHITECTURE.md`](./ARCHITECTURE.md) for the A/B/C/D layer diagram.

After `cargo install proof-forge-pf` you still need at least `proof-forge-next` on `PROOF_FORGE_CLI`.

Recommended full install paths:

1. **Monorepo / Release bundle** (preferred for end users): `just pf-cli-dist` → side-by-side `pf` + `proof-forge-next`
2. **crates.io** (orchestrator only): `cargo install proof-forge-pf --locked`
3. **Git install**: `cargo install --git <repo> --locked proof-forge-pf`

## Why not the crate name `pf`?

`pf` is already taken on crates.io (`pf = "0.0.0"`, unrelated).  
We publish as **`proof-forge-pf`**; the **binary name remains `pf`**.

## Pre-publish checklist

```bash
# 1) tests
just pf-cli-test
just pf-cli-smoke          # host-optional e2e

# 2) package dry-run (no upload)
just pf-cli-publish-dry-run

# 3) review .crate contents
#    ensure no secrets, no target/, includes README + LICENSE + INSTALL

# 4) login (once per machine)
cargo login                 # crates.io API token — do NOT commit

# 5) publish (maintainers only) — git tree must be clean under clients/pf-cli
git status --short clients/pf-cli    # must be empty
PF_PUBLISH=1 just pf-cli-publish
```

Cargo refuses dirty trees on real `cargo publish` (dry-run may use `--allow-dirty`).
Commit setup/docs changes first, then publish.


## Versioning

- Crate semver lives in `clients/pf-cli/Cargo.toml`
- Bump **before** publish (no overwrite of existing versions on crates.io)
- Tag git: `pf-v0.1.0` matching crate version when releasing

## Cargo.toml requirements (already wired)

- `name = "proof-forge-pf"`
- `license = "Apache-2.0"`
- `readme = "README.md"`
- `repository` / `homepage` / `documentation`
- `publish = true` (crate is intentionally publishable)
- `include` allow-list so we do not ship monorepo noise

## Post-publish smoke

```bash
cargo install proof-forge-pf --locked --force
pf --version
# still need compiler:
export PROOF_FORGE_CLI=/path/to/proof-forge-next
pf setup --target aleo
```

## Security

- Never put API tokens in repo or CI logs
- Prefer Trusted Publishing / restricted token scopes when wiring CI later
- `publish = true` does **not** auto-publish; humans (or gated CI) must run publish

## Related

- `INSTALL.md` — end-user install
- `scripts/pf_cli_dist.sh` — side-by-side binary bundle
- `docs/product/05-distribution-and-packages.md` — compiler tarball policy
