# `pf` — ProofForge developer CLI

`pf` is the Rust developer workflow wrapper around the authoritative
`proof-forge-next` compiler and official chain tools. It does not compile or
reinterpret ProofForge programs itself.

## 30 seconds

```bash
just pf-cli-build
export PROOF_FORGE_CLI="$PWD/.lake/build/bin/proof-forge-next"

clients/pf-cli/target/debug/pf doctor --target aleo
clients/pf-cli/target/debug/pf build Examples/StateCell.lean \
  --module Examples.StateCell --target aleo -o build/v2/statecell
clients/pf-cli/target/debug/pf local run --target aleo \
  --artifact build/v2/statecell -- initialize 5u64
```

Use `--json` for the stable `proof-forge.pf.result.v1` envelope. Run `pf
list-targets`, `pf check`, `pf inspect --artifact DIR`, or `pf --help` for the
remaining workflows.

## Environment

| Variable | Purpose |
|---|---|
| `PROOF_FORGE_CLI` | Absolute path to `proof-forge-next` |
| `PROOF_FORGE_ROOT` | Package/monorepo root |
| `PROOF_FORGE_TOOL_ROOT` | locked tool root |
| `PROOF_FORGE_ALEO_LEO` | optional explicit Leo executable |

## Network safety defaults

- Aleo deploy and execute are **save-only** unless `--broadcast` is explicit.
- Mainnet is refused in v0.
- Broadcast requires `--private-key-env NAME`; no key file is discovered from
  the working directory.
- The well-known Leo development key is refused for broadcast.
- Keys are not included in result JSON or artifact manifests.
- Aleo network packaging is fail-closed and currently accepts only the
  registered StateCell structural twin. Success is not a formal, hermetic, or
  mainnet maturity claim and never rewrites compiler `deployable` metadata.
