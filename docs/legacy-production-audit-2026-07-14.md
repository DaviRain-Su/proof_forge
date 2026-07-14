# Legacy Production Audit

Date: 2026-07-14

## Result

Every `Legacy`-named module below `ProofForge` was checked for inbound imports
and runtime callers. The obsolete test-only Core model, validator, partial
elaborator, elaborator smoke, and observable-refinement harness have been moved
to `TestFixtures/Legacy`. The production aggregate `ProofForge.IR` no longer
exports them, and `canonical-boundary` rejects restoring their old paths.

## Removed From Production

| Former module | Current owner | Reason |
|---|---|---|
| `ProofForge.IR.Legacy.Core` | `TestFixtures.Legacy.Core` | Superseded pre-Canonical Core model; only the historical elaborator tests used it |
| `ProofForge.IR.Legacy.Validate` | `TestFixtures.Legacy.Validate` | Validator for the superseded model; no compiler caller |
| `ProofForge.IR.Elaborate` | `TestFixtures.Legacy.Elaborate` | Deprecated partial translator; only two focused tests used it |
| `ProofForge.IR.Elaborate.Smoke` | `TestFixtures.Legacy.ElaborateSmoke` | Historical smoke fixture, not a production API |
| `ProofForge.IR.Legacy.Refinement` | `TestFixtures.Legacy.Refinement` | Dual-run evidence used only by Canonical migration tests |

## Remaining Production Cut Points

These modules still have production callers and are scheduled for deletion by
the authoring cutover rather than hidden behind renames:

1. `Frontend.ContractSpec.Normalize` and `IR.Legacy.Adapter*` are the current
   `contract_source` normalization path. The direct authored-contract frontend
   must replace them first.
2. `Backend.WasmHost.{Plan,NearModulePlan,NearAbiPlan,StructPlan,JsonReturn}.Legacy`
   still serve public NEAR/secondary-Wasm compilation and client generation.
   They are removed after the canonical Product route owns those plans.
3. `Compiler.CanonicalPipeline` and `Cli.ContractLoader` still expose
   `legacyV1`/`surfaceV2`; the unique current source entry replaces both.
4. `Cli.LegacyArgs` still feeds command dispatch. Native target-first commands
   must own all active invocations before it can be deleted.
5. `IR.Legacy.Classification` remains paired with the frozen source schema only
   until the last adapter caller is gone.

No other `Legacy`-named production module had zero callers at this checkpoint.
The exact `IR.Legacy` production import set remains enforced by
`scripts/canonical/legacy-production-imports.txt` and must decrease
monotonically during the remaining cutover.

## Verification

- `lake build TestFixtures`
- legacy Core/elaborator positive and negative smokes
- Canonical Legacy parity and refinement checks
- `scripts/canonical/check-legacy-freeze.sh`
- `scripts/canonical/check-boundary-self-test.sh`
- `scripts/canonical/check-boundary.sh`
- `lake build ProofForge.IR proof-forge`
