# Product SDK (author path)

**This is the only authoring surface you need for multi-chain contracts.**

```text
  You write:   business intent (state · entry · policies · token features · remote)
  You choose:  proof-forge build --target <evm|solana-sbpf-asm|wasm-near|…>
  Platform:    plan → materialize → encode → artifacts · clients · deploy
```

You do **not** write accounts, PDA, CPI, Promise, slots, selectors, ABI/JSON/ix
layouts, or token standards. Encoding is **always** plan-driven and internal.

Related deep dives (engine, not author menus):
[protocols-layer](protocols-layer.md) · [host-runtime](host-runtime.md) ·
[product-sdk-gap-plan](product-sdk-gap-plan-2026-07.md).

---

## 1. What to import

| Use | Import |
|-----|--------|
| Portable contract | `ProofForge.Contract.Source` |
| Token intent | `ProofForge.Contract.Token` |
| Stdlib mixins (Ownable, ERC-20 body, …) | `ProofForge.Contract.Stdlib.*` via Product examples / compose |

**Do not import for Product work:**

- `ProofForge.Contract.Source.Solana` / Solana Surface (Backend fixtures only)
- `ProofForge.Protocols.*` (compiler/materialize implementation of ecosystem calls)
- Backend EmitWat / Yul / Cpi modules

---

## 2. Quick start

```bash
# From a scaffolded project
lake env proof-forge init my-app
cd my-app
lake update
just build-evm
just build-solana
just build-near
```

Or in this monorepo:

```bash
just portable-default          # Product sources stay chain-neutral
just portable-counter-multi-target
just product                   # Product gate: matrix · counter · remote
just portable-tutorial         # + policies · token honesty · Solana accounts
```

Tutorial walkthrough: [tutorials/portable-shared-path.md](tutorials/portable-shared-path.md).

---

## 3. What the platform does per `--target`

| Layer | Who owns it |
|-------|-------------|
| IR + capabilities | Compiler |
| CapabilityPlan / TokenPlan / Module plan | Compiler |
| HostRuntime honesty (unsupported host effect) | Preflight / resolve |
| **Encode** (invisible) | Materializer |
| · EVM | AbiEncode plan → `ToYul.AbiEncode` `mstore` + CALL (Multicall Call[]) |
| · NEAR entry params | Borsh |
| · NEAR FT peer args | JsonEncode (NEP-141 objects) |
| · Solana CPI | Named `dataLayout` ix bytes (+ `BinaryLayout` LE field plans) |
| Artifacts · SDK schema · deploy | CLI |

Authors never pick Borsh vs JSON vs ABI.

---

## 4. Three trees (taxonomy hard line)

| Tree | Path | Role |
|------|------|------|
| **Product** | `Examples/Product/` | **Authoring** — business only |
| **Backend** | `Examples/Backend/` | Compiler goldens / fixtures — **not** the SDK menu |
| **Protocols** | `ProofForge/Protocols/` | Layer B clients used by materialize / advanced fixtures |

Gate: `just portable-default` rejects chain DSL in Product sources.

---

## 5. Token (three primary hosts)

| Target | Product command shape | Artifact |
|--------|----------------------|----------|
| `evm` | `build --target evm --token …` | ERC-20 Yul/bytecode |
| `solana-sbpf-asm` | `just product-token-solana` | SPL **plan** (`transfer_checked`, …) |
| `wasm-near` | `just product-token-near` | One parameterized NEP-141 Wasm package + generated clients/metadata |

Feature honesty: `just token-feature-matrix` (unsupported → reject, no silent drop).

```bash
just product-token-near     # NEAR TokenSpec -> Wasm + clients + metadata + real VM
just product-token-solana   # Solana TokenSpec SPL plan
just shared-token-intent    # Lean TokenSpec plan honesty (broader)
```

### 5.1 Call an external token (protocol intent)

Use Product protocol intent — **not** `import ProofForge.Protocols.*`:

```lean
external_token usdc "usdc.peer";
-- …
return externalTokenTransfer usdc to amount;
```

| Target | Materialize |
|--------|-------------|
| `evm` | IERC20 selector + CALL |
| `wasm-near` | NEP-141 `ft_transfer` + JsonEncode |
| `solana-sbpf-asm` | portable CPI smoke (live Tokenkeg needs plan/CPI path) |

```bash
just product-protocol-ft
```

---

## 6. Health commands

| Intent | Command |
|--------|---------|
| Product baseline | `just product` |
| Full portable tutorial | `just portable-tutorial` |
| Token feature matrix | `just token-feature-matrix` |
| NEAR token (plan + body) | `just product-token-near` |
| Solana token (SPL plan) | `just product-token-solana` |
| External FT protocol intent | `just product-protocol-ft` |
| External ERC-4626 vault | `just product-protocol-vault` |
| Deploy ERC-4626 vault body | `just product-erc4626-vault` |
| Deploy ERC20Permit body (EVM) | `just product-erc20-permit` |
| Multicall Call[] → Yul | `just multicall-abi-yul` |
| Engineering CI subset | `just check` |

### Product v1 freeze (2026-07-09)

Waves **α–ε** are **shipped and frozen** as the portable product slice:

- Token / external FT plans + protocol intent  
- ERC-4626 Layer C (pro-rata, fees, FOT vault+recipient deltas; EVM-primary)  
- ERC-2612 permit body + TokenSpec EVM merge  
- Multicall AbiEncode + IR `crosscallAbiPacked` (static / dyn len / targets / `DynCall`)  

**Not v1** (deferred): free-form Call `bytes`, fee-recipient re-measure,
VaultSpec-only authoring, non-EVM vault body parity. See
[product-sdk-gap-plan §0](product-sdk-gap-plan-2026-07.md).

---

## 7. Out of product scope (for now)

- Hand-written Solana CPI / account DSL as the default path  
- Importing Protocols clients in Product examples  
- New chain backends  
- Pretending every DeFi standard is portable  
- Free-form runtime ABI / nested dynamic Call data (v2 platform epic)  

Engine work (pack layers, HostRuntime, CPI catalogs) continues **under** this
surface — see [product-sdk-gap-plan](product-sdk-gap-plan-2026-07.md). Frozen
waves α–ε are the v1 claim; further edges need a named epic.
