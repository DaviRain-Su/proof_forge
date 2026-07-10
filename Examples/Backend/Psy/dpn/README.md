# Psy DPN bytecode goldens (Z1.1)

Normalized `DPNFunctionCircuitDefinition[]` JSON captured from `dargo compile`
of ProofForge-generated `.psy` sources.

| Golden | Source fixture | Notes |
|--------|----------------|-------|
| `Counter.golden.dpn.json` | `counter` | initialize / increment / get |
| `ArithmeticProbe.golden.dpn.json` | `arithmetic` | arithmetic_mix |
| `AssertProbe.golden.dpn.json` | `assert` | checked_sum + assertions |

Normalization: `scripts/psy/normalize-dpn-json.py`
Gate: `just psy-dpn-goldens`

**Toolchain pin (capture environment):** dargo path recorded in
`proof-forge-artifact.json` under `toolchain.dargo` when smokes run.
These goldens are the **bytecode** SOT for Z1; `.psy` goldens remain the
sourcegen SOT.

Regenerate (requires dargo):

```sh
just psy-smoke counter
just psy-smoke arithmetic
just psy-smoke assert
python3 scripts/psy/normalize-dpn-json.py \
  build/psy/dargo-counter/target/proof_forge_counter.json \
  -o Examples/Backend/Psy/dpn/Counter.golden.dpn.json
# similarly for arithmetic / assert package names
```
