# ProofForge SDK-V0 (Python)

Thin **Python** client that spawns the product CLI and parses JSON / on-disk
`proof-forge.output.v1` manifests. It is **not** a second compiler and does
**not** write Tool Lock tools via PATH fallback.

Authority: [`docs/product/01-toolchain-install-surface.md`](../../docs/product/01-toolchain-install-surface.md) §9.

## Install / import

No pip package. From package root (or set `PYTHONPATH`):

```bash
export PROOF_FORGE_ROOT=/absolute/path/to/proof_forge
export PYTHONPATH="$PROOF_FORGE_ROOT/tools/sdk${PYTHONPATH:+:$PYTHONPATH}"
# optional
export PROOF_FORGE_CLI="$PROOF_FORGE_ROOT/.lake/build/bin/proof-forge-next"
export PROOF_FORGE_TOOL_ROOT=/absolute/path/to/tool-root/linux-x86_64
```

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
# External ProgramV1 tree: pass root=... through build/check/local.
# r = client.local(target="aleo", source="src/Hello.lean", module="Hello", root="/tmp/external-pf")
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
| `local(target=…, mode=…, source=…, module=…, root=…, runs=…)` | `local --target … -- --source … --module … [--root …]` (Aleo sandbox generic; passes external project root when provided; no broadcast) |
| `chain_catalog(target=…)` | static chain client/frontend catalog (`proof-forge.chain-client-catalog.v1`) |
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
```

## Boundaries

- Target menu = `TargetRegistryV1` implemented only; design-only (`soroban` /
  `icp` / `openvm`) stay unsupported.
- Install never PATH-falls tools into `PROOF_FORGE_TOOL_ROOT`.
- Aleo snarkos remains I3 honesty (not Tool Lock; `features=test_network`).
- Does **not** set `deployable=true`; success is **not** formal / hermetic /
  mainnet evidence.
- No default network broadcast helper (use product CLI
  `network --broadcast` explicitly).

## Smoke

```bash
scripts/sdk_smoke.sh
```
