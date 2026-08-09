# External Aleo Hello (ProgramV1 template)

Minimal **out-of-monorepo-style** project: one `program Hello where` source, built and
sandbox-tested with a **separately installed** `proof-forge-next` CLI.

Authority:

- Product surface: [`docs/product/01-toolchain-install-surface.md`](../../docs/product/01-toolchain-install-surface.md)
- Aleo sandbox: [`docs/targets/09b-aleo-local-sandbox.md`](../../docs/targets/09b-aleo-local-sandbox.md)
- External author guide: [`docs/product/02-external-program-v1.md`](../../docs/product/02-external-program-v1.md)

## Layout

```text
external-aleo-hello/
  README.md          # this file
  src/Hello.lean     # ProgramV1 source (import ProofForgeV2 gate + program)
```

No Lake package is required for the product `build` / `local` path. The monorepo
`Examples/*` trees are **not** required after you copy this template.

## Prerequisites

1. Built product CLI: `proof-forge-next` (from this repo: `lake build proof_forge_next`).
2. Locked Leo 4.0.2 under `PROOF_FORGE_TOOL_ROOT` (or default cache tool-root).
3. Optional: `PROOF_FORGE_ROOT` pointing at the ProofForge package (for SDK/MCP).

```bash
export PROOF_FORGE_CLI=/absolute/path/to/proof_forge/.lake/build/bin/proof-forge-next
# optional if using default cache:
# export PROOF_FORGE_TOOL_ROOT=$HOME/.cache/proof-forge-v2/tool-root/linux-x86_64
```

## Build (any machine with the CLI)

From **this template directory** as project root:

```bash
"$PROOF_FORGE_CLI" build src/Hello.lean \
  --module Hello \
  --target aleo \
  --root "$PWD" \
  -o "$PWD/out-aleo"
```

Artifacts: `hello.aleo` (Instructions primary), `hello.aleo-query-contract.json`,
`manifest.json`. **`deployable=false`**.

## Local sandbox (offline interpret)

Generic sandbox (no Counter hardcoding). From the ProofForge package (so locked
scripts resolve), pass **this** directory as `--root`:

```bash
# from proof-forge package root:
./scripts/aleo_local_sandbox.sh \
  --root /absolute/path/to/external-aleo-hello \
  --source src/Hello.lean \
  --module Hello \
  --run 'initialize 1u64' \
  --run 'increment 2u64'

# or product local wrapper:
"$PROOF_FORGE_CLI" local --target aleo --mode sandbox -- \
  --root /absolute/path/to/external-aleo-hello \
  --source src/Hello.lean \
  --module Hello \
  --run 'initialize 1u64' \
  --run 'increment 2u64'
```

Maturity: `LEO-OFFLINE-RUN` local interpret only — **not** snarkVM package-only,
**not** chain deploy, **not** formal/mainnet.

## SDK / MCP

```python
from proof_forge_sdk import ProofForgeClient
c = ProofForgeClient()  # PROOF_FORGE_ROOT = monorepo
c.local(
    target="aleo",
    mode="sandbox",
    root="/absolute/path/to/external-aleo-hello",
    source="src/Hello.lean",
    module="Hello",
    runs=["initialize 1u64", "increment 2u64"],
)
```

MCP tool `pf_local`: same fields (`target`, `root`, `source`, `module`, `runs`).
**No** network broadcast tool.

## Honesty / remaining

| Claim | Status |
|---|---|
| Product build → Aleo Instructions | yes (engineering) |
| Offline `leo run` via sandbox | yes (host-heavy) |
| `deployable=true` / mainnet | **no** |
| MCP network deploy | **no** |
| formal Stage-0 | **no** |
| Multi-chain frontend catalog | remaining |
| Network demo | remaining (explicit CLI network receipt path, not MCP) |
| Lake syntax package | optional remaining |
