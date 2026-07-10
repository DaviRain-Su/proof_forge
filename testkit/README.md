# ProofForge Testkit

`testkit/` is the experimental unified scenario runner from RFC 0007. It owns
artifact-behavior tests that should eventually replace one-script-per-target
smokes.

Current scope:

- scenario discovery from `testkit/scenarios/*.toml`
- scenario manifest validation that rejects empty or duplicate target ids and
  artifact checks for targets not declared by the scenario
- optional scenario `source = "Examples/Product/*.lean"` inputs. Counter,
  ValueVault, ArrayExample (map/array), Ownable (auth/policy), and RemoteCall
  (crosscall) build from the same chain-neutral `.lean contract_source` modules
  through `proof-forge build --target ... --root .` before each harness executes
  target-native artifacts; fixture-only emission remains for focused
  compiler/runtime cases such as diagnostics and allocator probes
- typed scalar scenario args (`u64`, `u32`, `bool`) that each harness encodes
  into its native ABI (`Borsh`/little-endian input for `wasm-near`, ABI words
  for `evm`, and `[tag] + little-endian args` for `solana-sbpf-asm`)
- scenario-declared artifact checks through `[[artifact]]` entries, including
  golden-file equality (`matches_file`), text contains checks (`contains`),
  and structured JSON/TOML path assertions through nested `[[artifact.json]]`
  and `[[artifact.toml]]` checks for target metadata and manifests, including
  `exists`, `kind`, `non_empty`, and `length` assertions for presence, type,
  and array/object/table/string shape; nested
  `[[artifact.file]]` checks validate that JSON metadata file entries point at
  the harness artifact named by the scenario and match its path, byte size, and
  SHA-256 hash; nested `[[artifact.jsonArtifact]]` checks validate that a JSON
  value embedded in one artifact exactly matches another JSON artifact
- scenario-declared negative diagnostics through `[[diagnostic]]` entries;
  the first diagnostic-only scenario verifies that Solana rejects portable
  `crosscall.invoke` without a declared peer (PortableHonesty empty-peer fail-closed)
- `wasm-near` Counter, ValueVault, ArrayExample, and Ownable execution through
  the existing deterministic `runtime/offline-host` wasmtime host, using WAT and
  metadata produced from shared `contract_source`
- `evm` Counter, ValueVault, ArrayExample, and Ownable execution through an
  in-process `revm` harness that consumes target-first bytecode/Yul/metadata
  builds, loads artifact metadata selectors, and executes the same scenario
  steps as EVM transactions when Foundry `cast` is available for selector
  hydration
- `solana-sbpf-asm` Counter and ValueVault product scenarios execute the
  **source-built final ELF** (`artifactKind=solana-elf`, `sbpfBuild=passed`) via
  Mollusk (PF-P2-02); ArrayExample, Ownable, and RemoteCall still use
  intermediate assembly + harness scaffold when appropriate
- normalized observable trace parity across every selected target that ran
- `just testkit` and a CI gate

The testkit intentionally does not remove existing shell gates. Foundry and
Anvil remain the mature EVM runtime/deploy smokes; testkit is the portable
scenario layer for deterministic cross-target behavior comparison.

Run:

```sh
just testkit
```

Run only one target:

```sh
cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit -- run --target evm
cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit -- run --target wasm-near
cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit -- run --scenario value-vault
```

Print the raw per-call trace lines used for budget baselines:

```sh
cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit -- run --scenario value-vault --target solana-sbpf-asm --trace
```

List scenarios without executing them:

```sh
cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit -- list
```
