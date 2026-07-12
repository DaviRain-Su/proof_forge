# Product / SDK gap plan (2026-07)

Status: **Wave α–ε frozen as product v1** (2026-07-09)  
Audience: product + compiler  
North star: authors write **business intent only**; `--target` selects chain;
**encoding/layout is always plan → materialize** (authors never pack JSON/ABI/ix).

Related: [product-authoring-architecture](product-authoring-architecture.md),
[protocols-layer](protocols-layer.md), [host-runtime](host-runtime.md),
[portable-sdk-unification plan](superpowers/plans/2026-07-09-portable-sdk-unification.md),
[sdk-ecosystem-gaps](sdk-ecosystem-gaps-2026-07.md).

---

## 0. Product v1 freeze (2026-07-09)

**Shipped and frozen** — further honesty micro-edges are **v2 / deferred**, not
open blockers for product claims on this wave.

### v1 in scope (do not reopen without a product bug or new epic)

| Surface | v1 claim | Gate |
|---------|----------|------|
| Product path α–γ | portable examples, token NEAR/Solana plans, external FT intent | `just product*` / portable gates |
| Pack δ | EVM AbiEncode→Yul CALL; Solana BinaryLayout→CPI; Multicall object | `just multicall-abi-yul` |
| ERC-4626 Layer C | pro-rata floor; entry/exit `feeBps`; vault+recipient FOT deltas; EVM-primary IERC20 packing | `just product-erc4626-vault`, `Tests/ERC4626Stdlib` |
| ERC-2612 / permit | external client + stdlib body + TokenSpec EVM merge | `just product-erc20-permit` |
| Multicall IR ε | `crosscallAbiPacked`: static, dyn length, dyn targets, `DynCall` selector‖uint256* | `Tests/AbiEncode` |

### v2 / deferred (not “unfinished v1”)

| Item | Why deferred |
|------|----------------|
| fee-recipient push re-measure | No product bug; optional honesty edge |
| Free-form runtime Call `bytes` / nested dynamic ABI | Platform epic (`RuntimeAbiEncode`), not vault/product freeze |
| Performance fees / asymmetric OZ rounding matrix | Spec expansion epic |
| Solana/NEAR native “ERC-4626-shaped” deploy body | Different host semantics; EVM-primary honesty is intentional |
| VaultSpec-only author API (policy enums, no scratch slots) | Product UX epic on top of frozen body |

**Process:** new work needs a named epic or a failing author/gate case — not
default “continue honesty still open”.

---

## 1. Product shape (what “done” means for the SDK)

```text
  Developer
    · contract_source / TokenSpec / policies / remote intent
    · proof-forge build|check|deploy --target <id>
    · clients / artifacts / testkit
         │
         ▼
  Platform (invisible)
    · IR + CapabilityPlan + Token/Module plan
    · HostRuntime honesty
    · Pack layers (internal only):
        NEAR: JsonEncode (+ Borsh for *own* entry params)
        EVM:  AbiEncode
        Solana: CPI dataLayout / account schema
    · Emit · manifest · SDK schema · deploy
```

**Author never chooses:** layout, Borsh vs JSON vs ABI, account metas, PDA seeds
(except pure business seed literals via policy), TokenStandard.

---

## 2. What is already in good shape

| Area | Status | Notes |
|------|--------|--------|
| Portable default + Product examples | ✅ | `just portable-default`; Counter → Ownable → Token → Remote path |
| Multi-target Counter / Ownable / Remote | ✅ | EVM · Solana · NEAR (+ Soroban remote) |
| TokenSpec features-only | ✅ | `planForTarget`; matrix + honest rejects |
| Preflight L0/L1 + HostRuntime honesty | ✅ | n/a bindings fail resolve with clear text |
| Pack layer **existence** | ✅ | JsonEncode · AbiEncode · CPI layouts (internal) |
| Layer A/B/C naming | ✅ | Host · Protocols · Stdlib documented |
| Policy stdlib multi-host | ✅ | Ownable/Pausable/Reentrancy/AccessControl waves largely done |
| Error id catalog | ✅ | `portable-error-catalog` |

---

## 3. Where the product is still wrong or incomplete

### P0 — Breaks the north star (“I only pick --target”)

| # | Gap | Why it hurts | Desired |
|---|-----|--------------|---------|
| **P0.1** | **Two author surfaces** | Product path vs `Source.Solana` / Backend fixtures / Protocols Builder APIs look like “the SDK”. Easy to teach the wrong thing. | One default: Product. Chain DSL = fixture-only; CLI/docs never lead with it. |
| **P0.2** | **Token → Solana still plan-heavy** | Fungible TokenSpec produces plans/CPI *intent*; end-to-end “mint/transfer as user” often needs harness or extra steps, not one `build --target solana` mental model. | Single CLI: TokenSpec + target → deployable artifact + client smoke path. |
| **P0.3** | **Token → NEAR still two-step** | Plan + Stdlib body composition is real but not one button. | `build --target wasm-near --token` (or documented one-command alias) emits full FT. |
| **P0.4** | **“Call ecosystem token” not portable-intent** | IERC20 / SPL / NEP-141 peer clients exist as Layer B, but authors must still pick Protocols APIs or Backend fixtures—not `remote token.transfer` style intent. | Portable **protocol intent** (e.g. `token_transfer peer amount`) → plan picks IERC20 / SPL / NEP-141 packing. |

### P1 — Incomplete materialize of internal pack layers

| # | Gap | Desired |
|---|-----|---------|
| **P1.1** | ~~AbiEncode `Plan` not yet → Yul~~ | ✅ v1: `ToYul.AbiEncode` + IR `crosscallAbiPacked` (static / dyn len / targets / `DynCall`). Free-form bytes → **v2**. |
| **P1.2** | ~~Solana no BinaryLayout~~ | ✅ pure LE `BinaryLayout`; full Cpi rewrite still optional. |
| **P1.3** | Portable remote = scalar ABI only | Extend intentional types; or honest reject richer shapes. |
| **P1.4** | Solana account auto-fill incomplete for all product examples | Every Product example builds Solana without Surface. |

### P2 — SDK completeness / ecosystem

| # | Gap | Desired |
|---|-----|---------|
| **P2.1** | EVM: ERC-4626, permit, batch 1155, upgrade policy product story | Pick 1–2 P1 items from ecosystem gaps |
| **P2.2** | Client gen parity (TS/Rust) across three hosts | Same assertion ids + method names |
| **P2.3** | CLI legacy flags vs target-first | Finish M3/M4 migration narrative |
| **P2.4** | Docs: too many entry points | One “Product SDK” index page that links A/B/C as *engine*, not author menu |

### Conceptual traps (correct in code, wrong in messaging)

1. **Protocols ≠ product authoring** — Layer B is “how the platform calls Tokenkeg/IERC20”, not “please import Multicall.lean to ship”.  
2. **NEAR Borsh ≠ NEAR promise JSON** — entry params Borsh; FT peer args JSON.  
3. **Solana dataLayout ≠ general Borsh** — per-program ix bytes.  
4. **Pack layers are not author APIs** — JsonEncode / AbiEncode / CPI are compiler internals.

---

## 4. Recommended work plan (ordered)

### Wave α — Product clarity (docs + gates, small code)

**Goal:** One mental model; no new features.

1. **Product SDK index** — single doc: author path → CLI → what platform does (plan/encode).  
2. **Taxonomy hard line** — Product vs Backend vs Protocols in README / Examples.  
3. **CLI help / `proof-forge init` copy** — only portable path; chain DSL not in welcome.  
4. **Assert** Product examples still pass multi-target aggregate.

*Exit:* New contributor reads one page and never opens Cpi.lean.

### Wave β — Close the Token three-host product loop

**Goal:** Same TokenSpec → usable artifact on EVM · Solana · NEAR with one teaching path.

1. Unify NEAR token build to one documented command (alias ok).  
2. Solana token: define “done” = plan + package + one harness smoke (or honest “plan-only” label in CLI).  
3. Tutorial: one FungibleToken chapter, three targets, no layout words.

*Exit:* `just product` (or named token trio) green and teachable in 15 minutes.

### Wave γ — Protocol intent on the portable path

**Goal:** Authors express “transfer external token” without Protocols import.

1. Portable IR / Surface: minimal **protocol intent** nodes or sugar (token transfer / approve).  
2. Materialize:  
   - EVM → IERC20 selector + AbiEncode words  
   - Solana → SPL transfer_checked plan/CPI  
   - NEAR → NEP-141 JsonEncode object  
3. Product example + multi-target smoke.  
4. Keep Layer B clients as **implementation** of that materialize (not dual author API).

*Exit:* Shared example with no `Protocols.*` import; three hosts encode correctly.

### Wave δ — Finish pack materialize

**Goal:** Internal pack layers fully drive emit.

1. AbiEncode.Plan → Yul memory + CALL (Multicall real). ✅  
   `ToYul.AbiEncode.emitCall` / `renderAggregateCallYul`; Multicall facade.  
2. Solana BinaryLayout helper for new CPI layouts (optional hygiene). ✅  
   `Backend.Solana.BinaryLayout` pure LE field pack (sBPF still in Extension/Cpi).  
3. Permit2 / richer remote only if product-intent needs them.
   IR auto-lower of Call[] from portable `remoteCall` remains deferred.

### Wave ε — Ecosystem depth (selective)

Pick from sdk-ecosystem-gaps **only** where Product path needs them (e.g. one of ERC-4626 / permit / upgrade story)—not a full Solidity clone.

---

## 5. Explicit non-goals (now)

- New chain backends  
- Unifying all packs into Borsh  
- Authors writing dataLayout / ABI / JSON by hand  
- Infinite DeFi catalog (AMM, flash loan, …) until α–γ closed  

---

## 6. Execution status

| ID | Task | Status |
|----|------|--------|
| α.1 | Product SDK index (`docs/product-sdk.md`) | **done** |
| α.2 | Examples/README + CLI init/usage messaging | **done** |
| β.1 | `just product-token-near` (plan + NEP-141 body) | **done** |
| β.2 | `just product-token-solana` (SPL plan one-command) | **done** |
| γ.1 | Portable protocol intent (`external_token` + materialize) | **done** |
| γ.2 | `just product-protocol-ft` multi-target smoke | **done** |
| δ.1 | AbiEncode.Plan → Yul `mstore` + CALL (Multicall) | **done** |
| δ.2 | Solana BinaryLayout pure LE pack helper | **done** |
| δ.2b | BinaryLayout → static CPI stores (revoke/close/ATA) | **done** |
| δ.3 | Multicall Call[] full Yul object + `just multicall-abi-yul` | **done** |
| γ.3 | Product external approve path (`set_allowance`) | **done** |
| δ.2c | BinaryLayout Token-2022 static tags (pause/fee/…) | **done** |
| ε.1 | IERC4626 external client + `external_vault` product | **done** |
| ε.2 | EIP-2612 external `permit` client (call peer; not TokenSpec body) | **done** |
| ε.3 | ERC-4626 Layer C stdlib body (1:1 synthetic) | **done** |
| ε.4 | IR `ecrecover` + EIP-712 digest helpers (EVM) | **done** |
| ε.5 | ERC20Permit Layer C body (canonical atomic seven-argument `permit`) | **done** |
| ε.6 | ERC-4626 underlying pull/push via IERC20 remote | **done** |
| ε.7 | TokenSpec EVM `permit` plan → ERC20Permit stdlib notes | **done** |
| ε.8 | TokenSpec `moduleFor` merges ERC20Permit body when `permit` | **done** |
| ε.9 | ERC-4626 pro-rata rates (`convert` / deposit / withdraw floor) | **done** |
| ε.10 | ERC-4626 `preview*` + IERC4626 preview client selectors | **done** |
| ε.11 | ERC-4626 entry `feeBps` / `feeRecipient` on deposit·mint | **done** |
| ε.12 | Compile-time Call[] IR auto-lower (`crosscallAbiPacked`) | **done** |
| ε.13 | ERC-4626 exit fee + mint net shares / preview symmetry | **done** |
| ε.14 | ERC-4626 fee-on-transfer deposit/mint (balance delta) | **done** |
| ε.15 | Call[] runtime length via max-pack + length-word overwrite | **done** |
| ε.16 | ERC-4626 exit FOT (vault balance down-delta on push) | **done** |
| ε.17 | Call[] runtime targets + static calldata templates | **done** |
| ε.18 | ERC-4626 recipient-side FOT (recv balance up-delta) | **done** |
| ε.19 | Call[] runtime selector‖uint256* args (`aggregateIrDynCalls`) | **done** |
| **ε freeze** | Product v1 honesty freeze (this section §0) | **done** |

**v1 closed.** Deferred (v2 only): fee-recipient push re-measure; free-form
runtime calldata blobs; VaultSpec author API; multi-host vault body parity.

---

## 7. Success metrics

| Metric | Target |
|--------|--------|
| Author must open Solana CPI docs to ship Product | Never |
| “How do I encode for Solana?” in product tutorial | Zero mentions of layout |
| Token three-host health command | 1 command, green |
| Unsupported feature | Reject with plan/target name, not empty artifact |
| New contributor time to first multi-target Counter | ≤ 30 min with only Product docs |

---

## 8. Decision log (this review)

| Decision | Choice |
|----------|--------|
| Author vs pack layers | Pack = internal; plan-driven only |
| Borsh unify all chains | **No** |
| Solana CPI dataLayout | Keep; later BinaryLayout hygiene optional |
| Next code after this plan | α clarity → β token loop → γ portable protocol intent |
-/
