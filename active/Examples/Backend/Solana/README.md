# Solana sBPF Examples

This directory contains Solana-specific compatibility entrypoints, golden
assembly, and manifest fixtures for the canonical Solana route
`solana-sbpf-asm` (D-026): direct sBPF assembly codegen from the portable IR,
assembled and linked by the [blueshift-gg/sbpf](https://github.com/blueshift-gg/sbpf)
toolchain.

**Product authoring is not here.** Shared portable contracts live under
`Examples/Product` with `import ProofForge.Contract.Source` only. Account / PDA /
CPI syntax (`import ProofForge.Contract.Source.Solana`) is **fixture / research
only** — for backend goldens, Pinocchio gates, and hand-tuned layouts that the
portable materializer does not cover yet.

## `Counter.lean`

`Counter.lean` imports the canonical shared Counter source from
`Examples/Product/Counter.lean`; it preserves the historical Solana example path
without duplicating the contract logic. The generated module has three
entrypoints:

- `initialize` — writes `0` to the single scalar `count` account field.
- `increment` — reads `count`, adds one, and writes it back.
- `get` — returns `count` through `sol_set_return_data`.

The tracked golden assembly is compiled by the same backend fixture used by the
target-first `emit --target solana-sbpf-asm --fixture counter` command. Running
that command also writes a `manifest.toml` sidecar describing the instruction
tags and the single writable account owned by the program.

```sh
lake env proof-forge emit --target solana-sbpf-asm --fixture counter --format s \
  -o build/solana/Counter.s \
  --artifact-output build/solana/proof-forge-artifact.json
```

To build the Solana ELF (requires `sbpf` on `PATH`):

```sh
lake env proof-forge emit --target solana-sbpf-asm --fixture counter --format elf -o build/solana/Counter.so
```

The runtime half is exercised by `scripts/solana/counter-smoke.sh`, which
scaffolds an sbpf project from the emitted `.s`, builds the ELF, and runs the
Mollusk test harness.
