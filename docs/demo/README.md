# ProofForge Demo Recordings

## EVM Complete Workflow Demo

A terminal recording demonstrating the full ProofForge EVM workflow:

1. **Contract Authoring** — Lean 4 `contract_source` DSL
2. **Compilation** — `proof-forge build --target evm` (Lean → IR → Yul → bytecode)
3. **Deployment** — Local Anvil chain via `cast send --create`
4. **Testing** — Foundry IR smoke tests (all fixtures pass)

### How to Play

**Option A: Online (recommended)**

Upload the `.cast` file to [asciinema.org](https://asciinema.org) and share the link:

```sh
asciinema upload proofforge-evm-demo.cast
```

**Option B: Local playback**

```sh
asciinema play proofforge-evm-demo.cast
```

**Option C: Convert to GIF**

Install [agg](https://github.com/asciinema/agg) and run:

```sh
agg proofforge-evm-demo.cast proofforge-evm-demo.gif
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