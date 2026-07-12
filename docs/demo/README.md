# ProofForge Demo Recordings

## EVM Complete Workflow Demo

> **Watch online: https://asciinema.org/a/RDtrv79Std0p0ads**

A terminal recording demonstrating the full ProofForge EVM workflow:

1. **Contract Authoring** — Lean 4 `contract_source` DSL
2. **Compilation** — `proof-forge build --target evm` (Lean → IR → Yul → bytecode)
3. **Deployment** — Local Anvil chain via `cast send --create`
4. **Testing** — Foundry IR smoke tests (all fixtures pass)

### How to Play

**Option A: Online (recommended)**

Watch directly at **https://asciinema.org/a/RDtrv79Std0p0ads**

Or upload the `.cast` file yourself:

```sh
asciinema upload docs/demo/proofforge-evm-demo.cast
```

**Option B: Local playback**

```sh
asciinema play docs/demo/proofforge-evm-demo.cast
```

**Option C: Convert to GIF**

Install [agg](https://github.com/asciinema/agg) and run:

```sh
agg docs/demo/proofforge-evm-demo.cast docs/demo/proofforge-evm-demo.gif
```

### Recording Details

| Field       | Value                                    |
|-------------|------------------------------------------|
| File        | `proofforge-evm-demo.cast`               |
| Duration    | ~2 minutes                               |
| Terminal    | 80×24                                    |
| Format      | asciicast v3 (JSON)                      |
| Idle limit  | 2 seconds (long pauses auto-compressed)   |

### Re-recording

To regenerate the demo:

```sh
asciinema rec --idle-time-limit=2 \
  --command="scripts/demo/record-demo.sh" \
  docs/demo/proofforge-evm-demo.cast
```

The demo script (`scripts/demo/record-demo.sh`) runs the actual
ProofForge commands against the live toolchain — no mocks.
