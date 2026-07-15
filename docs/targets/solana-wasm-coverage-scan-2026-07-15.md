# Solana sBPF + Wasm assembly coverage scan (2026-07-15)

Status: **Evidence note** (branch PR #105). Not a maturity upgrade.
Related: D-026 (sBPF), D-031 (EmitWat), D-058 (no Rust product lower).

## Question

Is Lean “assembly-style” codegen for **Solana sBPF** and **Wasm/NEAR** complete
enough for real production, or are there remaining structural gaps we can still
surface with tests?

## Short answer

| Target | Can ship simple portable products? | Production-complete? |
|---|---|---|
| **EVM** (Yul→solc) | Yes for Ownable / Counter / ValueVault-class | Closest; still not “any Solidity” |
| **Solana sBPF** | Yes for Counter / ValueVault / GuestBook / Ownable / AccessControl (after large-imm fix) | **No** — Phase-1 hash, account/CPI depth, typed returns incomplete |
| **Wasm-NEAR (EmitWat)** | Yes for same portable scalar products | **No** — param/return/U128/bytes/JSON gaps; fixture CLI matrix incomplete |

**Neither Solana nor Wasm is “fully covering real production.”** Both are
**usable experimental/product slices** with **honest fail-closed** messages in
many unsupported cases, plus a few **silent semantic simplifications** (worst
kind of gap).

---

## What we tested (this scan)

### A. Portable products (`proof-forge build --target …`)

| Product | solana-sbpf-asm | wasm-near | Notes |
|---|---|---|---|
| Counter | OK | OK | Baseline |
| Ownable | OK | OK | |
| ValueVault | OK | OK | |
| Pausable | OK | OK | |
| GuestBook | OK | OK | |
| RemoteCall | OK | OK | |
| AccessControl | OK after imm fix | OK | Solana previously failed sbpf on `≥2^63` decimal imm; fixed `Asm.numStr` → hex |
| FungibleToken | needs `--token` | needs `--token` | CLI shape, not lower crash |
| Nft | needs `--nft` | needs `--nft` | Intent/NFT loader path |

### B. IR fixtures (`emit --fixture`)

Many ids **fail at CLI mapping** (`not yet mapped`), not always at lower:

| Fixture | Solana | NEAR | Nature |
|---|---|---|---|
| counter | OK | OK | |
| value-vault | OK | **not mapped** | Product ValueVault NEAR **does** build |
| context | not mapped | OK | |
| map | not mapped | OK | |
| assert / event / crosscall / array | not mapped | not mapped | Coverage debt in `Fixture.lean` |

So: **fixture matrix ≠ product coverage**. Production honesty must use **product
sources + runtime gates**, not only `emit --fixture`.

### C. Gates already in-repo (heavier than this scan)

`just solana-light`, `near-target-first`, `near-vm-conformance*`, Surfpool /
Pinocchio optional live, offline-host, etc. Those prove **fragments** (Counter
lifecycle, some CPI/PDA/sysvars), not universal IR.

---

## Structural gaps (more important than “build exit 0”)

### Solana sBPF assembly

| Gap | Evidence | Production impact |
|---|---|---|
| **Hash is Phase-1 limb0 only** | `SbpfAsm/Expr.lean`: `hash4 a _b _c _d` → `mov64` of limb0; “full four-limb deferred” | AccessControl roles / any full 32-byte identity are **not** true `keccak256` equality — only u64 handle |
| **Large immediates** | Was: decimal `≥2^63` broke `sbpf`; now hex | Fixed for assembler; still need care for any path that assumes i64 decimal |
| **Events** | Scalar `sol_log_64_` Phase 1; Anchor/Borsh event layout incomplete | Not Anchor-compatible event consumers |
| **Returns** | Typed payloads beyond u64 still limited | Complex ABIs incomplete |
| **Allocator / dynamic heap structures** | Metadata exists; dynamic structures not fully lowered | Large maps/arrays risk |
| **CPI / PDA** | Substantial but still expanding (try_find PDA, live matrix) | Fine for demos; not full Pinocchio surface |
| **Production deploy** | ELF via `sbpf`; live Surfpool optional | CI often stops at assemble/Mollusk |

### Wasm / NEAR EmitWat

| Gap | Evidence | Production impact |
|---|---|---|
| **Dynamic bytes/string params** | Only as **sole** parameter (`Params.lean`) | Multi-arg NEP methods with memo/string blocked if shape wrong |
| **U128** | Literals >U64, pow, some comparisons “not yet” | FT amounts need careful path; partial U128 helpers exist |
| **bytes / string literals** | Explicit refuse / pool limits | Authoring constrained |
| **JSON schema** | Unknown-field skip not implemented; strict object plans | Less tolerant than hand-written near-sdk |
| **CosmWasm / Soroban** | Separate bridges; Counter MVP / incomplete params | Not “Wasm universal” |
| **Fixture CLI** | `value-vault` not mapped for NEAR emit while product works | Tooling confusion |

### Shared honesty

- **Build success ≠ production semantics.** Especially Solana **hash limb0**.
- **Fail-closed is good** when EmitWat throws; **silent subset semantics**
  (limb0 hash) is the bigger production risk.
- **EVM is still the most complete handoff** (Yul + solc industry backend).

---

## Can we test more? Yes — recommended next tests

| Priority | Test | Why |
|---:|---|---|
| **P0** | Hash limb0 honesty test: two `hash4` values same limb0 different other limbs must not be treated as equal if product claims full hash | Catch silent security bug class |
| **P1** | Expand `emit --fixture` mapping for NEAR value-vault / solana map to match product | Reduce false “unsupported” noise |
| **P1** | AccessControl **runtime** role check on Solana (Mollusk/Surfpool), not only `sbpf build` | Prove limb0 is or isn’t acceptable |
| **P2** | NEP-141 product via `--token` + `near-vm-conformance-ft` regularly on #105 | Real FT path |
| **P2** | Multi-param JSON entry with string + scalar on NEAR | Hit sole-parameter rule intentionally |
| **P3** | U128 amount > 2^64-1 literal | Expect fail-closed |
| **P3** | Live Surfpool / near-sandbox only when tools present | Don’t fake green without tools |

Commands already useful:

```bash
just solana-asm-imm
just access-control-solana-smoke
just ownable-evm-smoke
# heavier:
# just solana-light
# just near-vm-conformance-product
```

---

## Completeness score (subjective, for planning)

| Dimension | EVM | Solana sBPF | Wasm-NEAR |
|---|---|---|---|
| Portable scalar product compile | High | High | High |
| External packager maturity | High (solc) | Medium (sbpf) | Medium (wat2wasm) |
| Host/runtime fidelity | High | Medium | Medium (offline host / near-vm slice) |
| Full IR surface | Medium | Low–Medium | Low–Medium |
| Ecosystem ABI (Anchor/NEP full) | Medium (Solidity-ish) | Low | Medium (NEP partial) |
| Ready to call “production compiler” | **No** (experimental product) | **No** | **No** |

Public beta language in AGENTS (“experimental” triad) remains appropriate.

---

## Implications under D-058

- Gaps are **Lean lower + host fidelity** problems, not “need Rust assembler.”
- Improving coverage means: **finish Phase-1 hash**, widen EmitWat params,
  map fixtures honestly, add **runtime** dual-run — not rewrite printers in Rust.
- Seam A inspect dual-run (entrypoints/slots) does **not** prove Solana/Wasm
  production correctness.

---

## Bottom line

1. **拼装（AST→文本→外部工具）对主 portable 产品能跑通**，但  
2. **远未覆盖“真实生产全部语义”**，最大隐忧是 Solana **Hash/limb0** 与  
   NEAR **参数/U128/bytes 子集**；  
3. **还能再测**：优先 hash 诚实性 + AccessControl 运行时 + fixture 映射债 + FT token 路径。
