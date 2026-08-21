# ProofForge SDK-V0 (Python)

Thin **Python** client that spawns the product CLI and parses JSON / on-disk
`proof-forge.output.v1` manifests. It is **not** a second compiler and does
**not** write Tool Lock tools via PATH fallback.

Authority: [`docs/product/01-toolchain-install-surface.md`](../../docs/product/01-toolchain-install-surface.md) §9.

## Install / import

### Engineering-dist (recommended)

```bash
# From PyPI after tag release (Trusted Publishing):
pip install proof-forge-sdk==0.1.1

# Or from GitHub Release asset / local package:
# pip install ./proof_forge_sdk-0.1.0-py3-none-any.whl

export PROOF_FORGE_CLI=/path/to/proof-forge-next   # required for most calls
# optional: CLI dist root for doctor/install engines
# export PROOF_FORGE_ROOT=/path/to/proof-forge-next-0.1.0-linux-x86_64
```

Publish docs and PyPI Trusted Publisher setup table: [`docs/product/06-pypi-host-sdk.md`](../../docs/product/06-pypi-host-sdk.md).

### From monorepo (development)

```bash
export PROOF_FORGE_ROOT=/absolute/path/to/proof_forge
export PYTHONPATH="$PROOF_FORGE_ROOT/tools/sdk${PYTHONPATH:+:$PYTHONPATH}"
export PROOF_FORGE_CLI="$PROOF_FORGE_ROOT/.lake/build/bin/proof-forge-next"
```

Build wheel locally: `just package-host-sdk` → `dist/*.whl`.

```python
from proof_forge_sdk import ProofForgeClient, load_output_manifest

client = ProofForgeClient()
print(client.list_targets().parsed)
print(client.doctor(targets=["quint"]).parsed)
# Non-interactive plan only:
print(client.install(targets=["quint"], dry_run=True).parsed)
# After a product build:
# r = client.build("Examples/Counter.lean", module="Examples.Counter",
#                  target="quint", output="/tmp/pf-out")
# Compiler-local runtime entry point (host-heavy; availability is not release evidence):
# r = client.local(target="near", mode="runtime")
# manifest = client.load_output_manifest("/tmp/pf-out")
```

## API surface

| Method | CLI mapping |
|---|---|
| `list_targets(include_all=False)` | `list-targets [--all] --json` |
| `doctor(targets=…, with_runtime=…)` | `doctor --json` → `proof-forge.doctor.v1` |
| `install(targets=…, all_core=…, dry_run=…, yes=True)` | `install --yes/--dry-run --json` |
| `build(source, module=…, target=…, output=…)` | `build … --json` (no network/broadcast) |
| `check(source, module=…)` | `check … --json` |
| `inspect_artifacts(output_dir)` | `inspect --output-dir … --json` |
| `inspect_target(target)` | `inspect <target> --json` |
| `local(target=…, mode="runtime", script_args=…)` | `local --target <evm|solana|near|cosmwasm|ton|icp> --mode runtime [--] [script args…]`; other registered build targets fail closed; no broadcast |
| `chain_catalog(target=…)` | static chain client/frontend catalog (`proof-forge.chain-client-catalog.v1`) |
| `network_catalog(id=… / target_family=… / env=… / chain_id=…)` | static network catalog (`proof-forge.network-catalog.v1`, X Layer / Anvil) |
| `load_output_manifest(output_dir)` | parse `manifest.json` (`schemaVersion=proof-forge.output.v1`) |

`CliResult` fields: `ok`, `exit_code`, `command`, `stdout`, `stderr`, `parsed`,
`error`, `product_ok` (also camelCase in `to_dict()`).

## CLI helper

```bash
/usr/bin/python3 -I tools/sdk/proof_forge_sdk.py --self-check
/usr/bin/python3 -I tools/sdk/proof_forge_sdk.py doctor --target quint
/usr/bin/python3 -I tools/sdk/proof_forge_sdk.py install --targets quint --dry-run
/usr/bin/python3 -I tools/sdk/proof_forge_sdk.py load-manifest /path/to/output
/usr/bin/python3 -I tools/sdk/proof_forge_sdk.py chain-catalog --target aleo
/usr/bin/python3 -I tools/sdk/proof_forge_sdk.py network-catalog --id evm.xlayer.testnet
/usr/bin/python3 -I tools/sdk/proof_forge_sdk.py network-catalog --target-family evm --env testnet
```

## Boundaries

- Target menu = the 13-target `TargetRegistryV1` development/build surface; accepted
  Phase 1 remains EVM/Solana/NEAR/Noir. The compiler-local runtime subset is
  independently the six targets listed above. OpenVM remains engineering
  source-only / opt-in guest-elf (no prove install).
- Install never PATH-falls tools into `PROOF_FORGE_TOOL_ROOT`.
- Aleo snarkos remains I3 honesty (not Tool Lock; `features=test_network`).
- Does **not** set `deployable=true`; success is **not** formal / hermetic /
  mainnet evidence.
- No network broadcast helper; the compiler product has no `network` subcommand.

## Smoke

```bash
scripts/sdk_smoke.sh
```
