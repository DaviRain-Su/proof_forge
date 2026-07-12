# D4: Native NFT Target-First Dispatch

**Date:** 2026-07-12  
**Program:** D-052 Portable Intent and Target Promotion  
**Task:** D4 — Replace `newCommandArgsToLegacy` reparse with typed native target driver (NFT-only)  
**Authoritative plan:** [`docs/superpowers/plans/2026-07-12-incremental-legacy-replacement.md`](../plans/2026-07-12-incremental-legacy-replacement.md)

---

## Goal

Make the NFT `build` path on the three primary targets (`evm`, `solana-sbpf-asm`, `wasm-near`) go through a typed native target driver instead of being translated into legacy flags and reparsed. Non-NFT paths (Counter, ValueVault, Token, RemoteCall, fixtures, research targets) continue to use the legacy round-trip until their own migration tasks (D5-D12).

## Legacy boundary

`ProofForge.Cli.TargetFirst.newCommandArgsToLegacy` rewrites target-first `build` requests into old `--evm-bytecode`, `--contract-source-sbpf`, `--contract-source-emitwat`, etc. flags, then `ProofForge.Cli.LegacyArgs.parseArgs` reparses them into `CliOptions`. For NFT this means the same typed request is serialized to strings and immediately reconstructed.

## Replacement

A registry-backed native dispatch where `TargetCliDriver.resolveBuild` returns a `BuildResult` that explicitly marks the request as `.native` or `.legacy`. NFT requests on primary targets are `.native`; everything else remains `.legacy` for now.

## In scope

- `proof-forge build --target <primary> --nft <lean-source>` for `evm`, `solana-sbpf-asm`, `wasm-near`.
- Preserving artifact output, yul/assembly output, artifact metadata, constructor options, `--root`, `--module`, `--solc`, `--cast`, `--solana-sbpf-arch`, `--peer`, `--peers-demo`, `-o`, `--artifact-output`.
- Tests that pin `.native` dispatch kind for NFT and `.legacy` for non-NFT.
- Ledger update marking the NFT subrow of D4 `default_switched` while keeping D4 overall `replacement_ready`.

## Out of scope

- Removing `newCommandArgsToLegacy`, `LegacyArgs`, or `EmitMode` entirely (M4 later).
- Making `emit` or `check` native for NFT (`check` is already native; `emit --nft` does not exist today).
- Migrating Counter, ValueVault, Token, RemoteCall, or secondary targets.

---

## Architecture

### New types in `ProofForge/Cli/TargetDriver.lean`

```lean
inductive DispatchKind
  | legacy
  | native
  deriving BEq, Repr

inductive NativeBuildOp
  | nftEvmBytecode
  | nftSolanaSbpf
  | nftNearEmitWat
  deriving BEq, Repr

structure BuildResult where
  dispatchKind : DispatchKind
  legacyFlag? : Option String := none
  nativeOp? : Option NativeBuildOp := none
  deriving Repr
```

`TargetCliDriver.resolveBuild` returns `Except String BuildResult` instead of `Except String String`.

### Driver behavior

Primary triad `resolveBuild` functions return `.native` only when:

```lean
req.nft && isLeanSourceFile req.input?
```

Otherwise they return the existing `.legacy` flag.

| Target | Native condition | `NativeBuildOp` |
|---|---|---|
| `evm` | `req.nft && isLeanSource` | `nftEvmBytecode` |
| `solana-sbpf-asm` | `req.nft && isLeanSource` | `nftSolanaSbpf` |
| `wasm-near` | `req.nft && isLeanSource` | `nftNearEmitWat` |

All other drivers remain `.legacy`.

### CLI dispatch in `ProofForge/Cli.lean`

The `build` branch:

1. Parse `rest` into `NewCommandParseState` via `parseNewOptions`.
2. Convert `state` to `(targetId, BuildRequest)` via a new helper in `TargetFirst.lean`.
3. Call `TargetDriver.resolveBuild targetId req`.
4. If `.native op`:
   - Construct a `CliOptions` value directly from `state` (no string reparsing).
   - Set `cmd := .build`, `mode` to the matching legacy `EmitMode` (so existing compiler functions work unchanged), `nft := true`, `targetId? := some targetId`, `fromNewSurface := true`.
   - Using `EmitMode` here is an internal compiler-dispatch convenience; no user-visible flag string is produced or reparsed. `EmitMode` removal is out of scope (M4).
   - Dispatch to the existing compiler function:
     - `nftEvmBytecode` → `compileContractSourceEvmBytecode`
     - `nftSolanaSbpf` → `compileContractSourceSbpf`
     - `nftNearEmitWat` → `compileContractSourceEmitWat`
5. If `.legacy flag`:
   - Continue through `newCommandArgsToLegacy` → `parseArgs` → `compileFile` exactly as today.

### Helper in `ProofForge/Cli/TargetFirst.lean`

Add `resolveBuildRequest : NewCommandParseState → Except String (String × BuildRequest)` to centralize conversion of parsed state into the driver request. It validates that `--target` is present and copies `input?`, `fixture?`, `format?`, `token`, `nft` into `BuildRequest`.

### Output-path helpers

`targetFirstNativeOutput` and `targetFirstYulOutput?` remain in `TargetFirst.lean` and are called by the native dispatcher when constructing `CliOptions.output?` and `CliOptions.yulOutput?`.

---

## Data flow

Example:

```bash
proof-forge build --target evm --nft Examples/Product/Nft.lean -o build/evm/Nft.bin
```

1. `parseNewOptions` → `state` with `target? = some "evm"`, `nft = true`, `input? = some "Examples/Product/Nft.lean"`, `out? = some "build/evm/Nft.bin"`.
2. `resolveBuildRequest state` → `("evm", { nft := true, input? := some "...", ... })`.
3. `evmResolveBuild req` sees `req.nft && isLeanSource` and returns `.native nftEvmBytecode`.
4. `Cli.lean` builds `CliOptions`:
   - `mode := .evmBytecode`
   - `nft := true`
   - `input? := FilePath.mk "Examples/Product/Nft.lean"`
   - `output? := FilePath.mk "build/evm/Nft.bin"`
   - `yulOutput? := targetFirstYulOutput?` resolved value
   - constructor, root, module, solc/cast, peer options copied from `state`
5. Calls `compileContractSourceEvmBytecode opts`.
6. `loadContractSpecForOptions` sees `opts.nft` and calls `NftLoader.loadAndMaterializeNft`, which runs the strict canonical gate and returns the materialized `ContractSpec`.
7. Existing EVM bytecode pipeline emits `build/evm/Nft.bin` and Yul/artifact metadata.

---

## Error handling

- Missing `--target`: `resolveBuildRequest` errors before driver lookup.
- Unknown target: `TargetDriver.resolveBuild` errors with `unknown target '<id>'`.
- NFT + non-Lean input: primary driver returns existing diagnostics, e.g. `proof-forge build --target evm --nft requires a .lean NFTSpec source`.
- Native path failures (materialization, canonical gate, compiler) propagate through `IO`/`Except` as today.
- Native path diagnostics must not mention translated legacy flags such as `--evm-bytecode`.

---

## Testing

### Unit tests in `Tests/CliTargetFirst.lean`

- For each primary target, construct a `BuildRequest` with `nft := true` and a `.lean` input; assert `dispatchKind == .native` and `nativeOp` matches.
- Assert Counter/Token fixture requests still return `.legacy` with a non-empty `legacyFlag?`.
- Assert unknown target returns `Except.error`.
- Assert NFT + non-Lean input returns `Except.error`.

### Schema / artifact tests

- `Tests/NftArtifactSchema.lean` continues to pass; update only if the native path changes observable schema fields.

### Integration tests

- `scripts/portable/nft-multi-target.sh`
- `just product`
- `just check`
- `git diff --check`

---

## Files changed

- `ProofForge/Cli/TargetDriver.lean` — new result types, update primary triad `resolveBuild`.
- `ProofForge/Cli/TargetFirst.lean` — add `resolveBuildRequest`, keep `newCommandArgsToLegacy` for legacy paths.
- `ProofForge/Cli.lean` — native dispatch in `build` branch.
- `Tests/CliTargetFirst.lean` — native-dispatch assertions.
- `Tests/NftArtifactSchema.lean` — update if schema assertions need adjustment.
- `scripts/portable/nft-multi-target.sh` — update if CLI invocation changes.
- `docs/legacy-replacement-ledger.md` — D4 NFT subrow to `default_switched`.
- `docs/implementation-log.md` — D4 entry.
- `AGENTS.md` — checkpoint.
- `docs/superpowers/plans/2026-07-12-incremental-legacy-replacement.md` — D4 checklist.

---

## Removal gate (D4 overall, not this slice)

D4 as a whole reaches `default_switched` only when every product family build/emit/check is native. This slice only switches NFT; the ledger must record that partial state explicitly.
