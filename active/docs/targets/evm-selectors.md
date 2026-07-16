# EVM ABI selectors (product + Seam A)

Status: **Current** (2026-07-15). Complements D-046 (EVM product pipeline) and
D-058 (no Rust product lower). Chinese: none yet; EN is source of truth.

## Why this note exists

Portable `contract_source` methods often omit a pinned 4-byte selector.
EVM `buildFromCore` requires a selector on every function entrypoint. Product
Yul emission and dual-run observe must agree on how missing selectors are filled
without re-opening a Rust codegen path.

## Three sources of truth (priority)

| Priority | Source | When used |
|---:|---|---|
| 1 | **Pinned `selector?` on IR / method** | Fixtures and materializers that set an explicit hex string (e.g. Counter `initialize` → `8129fc1c`). **Not re-derived** by missing-only hydrate. |
| 2 | **Pure Lean keccak** (`ProofForge.Util.Keccak256.selectorHex`) | Default fill for missing selectors: first 4 bytes of Ethereum Keccak-256 of the Solidity ABI signature string (e.g. `owner()` → `8da5cb5b`). No Foundry required. |
| 3 | **Foundry `cast sig`** | Product CLI `hydrateEvmSelectors` prefers `cast` when available; result must match Lean keccak. If `cast` is missing or fails, **Lean is used** (`selectorFor` fallback). |

## Signature spelling

Lean builds the ABI signature via `entrypointSoliditySignature` / `AbiType.typeName`
(Solidity-oriented spellings such as `uint256` for many portable integers when
mapped for ABI). **Pinned fixture selectors may intentionally not match a
`cast sig` of a different spelling** (e.g. historical `u64` vs `uint256`).

Policy:

- **Product path (strict):** `hydrateEvmSelectors` validates that any **pinned**
  selector matches the derived signature. Mismatch → hard error.
- **Dual-run / missing-only:** `hydrateEvmSelectorsMissing` / `…MissingLean`
  **only fills `none`**; pinned values are left alone (avoids breaking IR
  fixtures that pin non-canonical spellings).

## Where it is wired

| Path | Module |
|---|---|
| Product Yul | `ProofForge/Cli/EvmArtifacts.lean` → `hydrateEvmSelectors` before `buildFromCore` |
| Selector derive | `ProofForge/Cli/EvmAbi.lean` → `selectorFor` / `selectorForLean` |
| Dual-run observe | `Tests/Canonical/DualRunObserve.lean` → Lean missing-only hydrate |
| Vectors | `Tests/Util/Keccak256.lean`, `just keccak256` |

## What this is not

- Not a Rust lowerer and not bytecode dual-run (D-058).
- Not a promise that every portable type maps to the same Solidity string as
  every historical fixture pin — pins win until fixtures are deliberately
  refreshed.

## Local commands

```bash
just keccak256
just dual-run-observe-seam-a
just ownable-evm-smoke   # product Ownable → Yul → solc (when wired)
```
