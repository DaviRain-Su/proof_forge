# Legacy Replacement Ledger

Status: **Current executable migration ledger (2026-07-12)**

| Boundary ID | Legacy entry | Replacement | State | Trigger | Removal condition | Evidence |
|---|---|---|---|---|---|---|
| D1-source-solana | Solana grammar reachable from `Contract.Source` | `Contract.Source.Solana` ownership | inventoried | A1 | portable reject + Solana parity | pending |
| D2-product-spec | product entry directly routes `ContractSpec` | `IntentContract` materializer | inventoried | A2-A6 | each product family switched | pending |
| D3-canonical-fallback | advisory `runCanonicalValidationGate` | strict canonical target gate | inventoried | A5/B2 | advertised fragments strict by default | pending |
| D4-cli-arg-roundtrip | `newCommandArgsToLegacy` reparse | typed native target driver | inventoried | A6 | build/emit/check native | pending |
| D5-legacy-imports | production imports `IR.Legacy.*` | canonical or isolated test helper | inventoried | D6-D12 | production allowlist empty | pending |

## State Lifecycle

Each boundary moves through five states:

1. **inventoried** — legacy entry identified, replacement named, freeze baseline captured
2. **replacement_ready** — replacement implemented and tested in parallel
3. **parity_verified** — replacement produces identical or improved behavior under named gates
4. **default_switched** — replacement is the default path; legacy is opt-in or advisory
5. **removed** — legacy code path deleted; freeze guard updated; no production caller remains

A boundary may not skip states. A state transition requires a revision and
reproducible positive and negative gates.

## D1-source-solana

- **Legacy:** Solana-specific `declare_syntax_cat` and `scoped syntax` productions in `ProofForge/Contract/Source.lean`
- **Replacement:** `ProofForge/Contract/Source/Solana.lean` owns all Solana-only syntax
- **Trigger:** A1 (Isolate Solana Grammar Ownership)
- **Parity:** `just portable-default` (portable rejects Solana forms) + `just solana-light` (Solana fixtures compile)
- **Current evidence:** A1 committed at `52402821`; `Tests/SourceDslIsolation.lean` passes
- **Next state:** `removed` after D1 closes the guard

## D2-product-spec

- **Legacy:** product `contract_source` and `TokenSpec` routes produce `ContractSpec` directly
- **Replacement:** `IntentContract` → `IntentMaterializer` registry → `ContractSpec` via materializer
- **Trigger:** A2-A6 (Intent materializer + NFT vertical slice)
- **Parity:** each product family has native + canonical parity under `just product`
- **Current evidence:** none yet
- **Next state:** `replacement_ready` after A2 implements the registry

## D3-canonical-fallback

- **Legacy:** `runCanonicalValidationGate` is advisory — `buildFromCore` failures do not block
- **Replacement:** `runStrictCanonicalTargetGate` — all failures are hard errors
- **Trigger:** A5/B2 (strict canonical target gate)
- **Parity:** all primary-triad fixtures pass strict gate
- **Current evidence:** advisory gate committed in Wave 6 Task 18-22
- **Next state:** `replacement_ready` after B2 implements strict gate

## D4-cli-arg-roundtrip

- **Legacy:** `newCommandArgsToLegacy` reparses native target requests into legacy flags
- **Replacement:** typed `TargetDriver` dispatch with native build/emit/check
- **Trigger:** A6 (open the NFT CLI and product route)
- **Parity:** build/emit/check produce identical artifacts via native vs legacy paths
- **Current evidence:** none yet
- **Next state:** `replacement_ready` after A6 implements native CLI

## D5-legacy-imports

- **Legacy:** production `ProofForge/` modules import `ProofForge.IR.Legacy.*`
- **Replacement:** canonical pipeline (`adaptLegacy` → `validateCanonical` → `buildFromCore`) or isolated test helpers
- **Trigger:** D6-D12 (incremental migration of Counter, ValueVault, Token, RemoteCall, etc.)
- **Parity:** each migrated module passes strict canonical gate
- **Current evidence:** baseline captured in `scripts/canonical/legacy-production-imports.txt`
- **Next state:** `replacement_ready` as each module migrates